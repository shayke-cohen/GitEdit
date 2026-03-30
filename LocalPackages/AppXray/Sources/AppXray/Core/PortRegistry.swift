import Foundation

#if DEBUG

/// Manages ~/.appxray/ports.json so the MCP server can discover apps without
/// blind port scanning. Each SDK instance registers on bind and removes on stop.
/// File-level flock ensures safe concurrent access from multiple processes.
enum PortRegistry {
    private static let storeDir: String = {
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(".appxray")
    }()

    private static var filePath: String {
        (storeDir as NSString).appendingPathComponent("ports.json")
    }

    struct Entry: Codable {
        let port: UInt16
        let pid: Int32
        let appId: String
        let appName: String
        let platform: String
        let boundAt: TimeInterval
    }

    static func register(port: UInt16, appId: String, appName: String, platform: String) {
        let entry = Entry(
            port: port, pid: ProcessInfo.processInfo.processIdentifier,
            appId: appId, appName: appName, platform: platform,
            boundAt: Date().timeIntervalSince1970
        )
        withLockedFile { entries in
            entries.removeAll { $0.port == port }
            entries.append(entry)
        }
    }

    static func remove(port: UInt16) {
        let pid = ProcessInfo.processInfo.processIdentifier
        withLockedFile { entries in
            entries.removeAll { $0.port == port && $0.pid == pid }
        }
    }

    static func readAll() -> [Entry] {
        ensureDirectory()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }

    // MARK: - Internal

    private static func ensureDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storeDir) {
            try? fm.createDirectory(atPath: storeDir, withIntermediateDirectories: true)
        }
    }

    private static func withLockedFile(_ mutate: (inout [Entry]) -> Void) {
        ensureDirectory()
        let url = URL(fileURLWithPath: filePath)
        let fd = open(filePath, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }

        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }

        var entries: [Entry]
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }

        let myPid = ProcessInfo.processInfo.processIdentifier
        entries.removeAll { entry in
            if entry.pid == myPid { return false }
            return !isProcessAlive(entry.pid)
        }

        mutate(&entries)

        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
}

#endif
