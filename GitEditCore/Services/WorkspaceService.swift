import Foundation

/// Manages workspace folder scanning and file tree construction.
public final class WorkspaceService: Sendable {

    public init() {}

    /// Scan a directory and build a file tree of WorkspaceItems.
    @MainActor
    public func scanDirectory(at url: URL, depth: Int = 0, maxDepth: Int = 10) throws -> [WorkspaceItem] {
        guard depth < maxDepth else { return [] }

        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        )

        var items: [WorkspaceItem] = []

        for itemURL in contents.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            let isHidden = resourceValues.isHidden ?? false
            let isDirectory = resourceValues.isDirectory ?? false

            // Skip hidden files except .env
            if isHidden && !itemURL.lastPathComponent.hasPrefix(".env") {
                continue
            }

            let item = WorkspaceItem(
                url: itemURL,
                isDirectory: isDirectory,
                depth: depth
            )

            if isDirectory {
                let children = try scanDirectory(at: itemURL, depth: depth + 1, maxDepth: maxDepth)
                item.children = children
            }

            items.append(item)
        }

        // Sort: directories first, then files
        return items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Read file content as a string.
    public func readFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Write content back to file.
    public func writeFile(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Get file size in bytes.
    public func fileSize(at url: URL) throws -> UInt64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.size] as? UInt64 ?? 0
    }

    /// Check if a URL is within a git repository (has a .git directory ancestor).
    public func isInGitRepo(url: URL) -> Bool {
        var current = url.deletingLastPathComponent()
        while current.path != "/" {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return true
            }
            current = current.deletingLastPathComponent()
        }
        return false
    }

    /// Find the git repository root for a given path.
    public func gitRepoRoot(for url: URL) -> URL? {
        var current = url.deletingLastPathComponent()
        while current.path != "/" {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }
}
