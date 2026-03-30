import Foundation
#if canImport(OSLog)
import OSLog
#endif

#if DEBUG

/// Captures stdout/stderr output for inspection via console.list.
/// Uses pipe/dup2 to intercept file descriptors while forwarding to original destinations.
/// On macOS, also flushes C stdio buffers to ensure print() output is captured immediately.
///
/// Note: Only captures `print()` / `fputs(stdout)` output.
/// `os_log` / `Logger` output goes directly to the OS logging subsystem and
/// bypasses file descriptors — use `AppXray.shared.log()` for those.
final class ConsoleBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.appxray.console", qos: .userInitiated)
    /// Lock-protected entries array — readability handlers fire on GCD background
    /// queues and must not contend with the serial `queue` used by startCapture/list.
    private let entriesLock = NSLock()
    private var entries: [[String: Any]] = []
    private let maxEntries = 200
    private var isCapturing = false

    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutSource: DispatchSourceRead?
    private var stderrSource: DispatchSourceRead?
    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1

    func startCapture() {
        var captureOk = false
        queue.sync {
            guard !isCapturing else { return }
            isCapturing = true

            fflush(stdout)
            fflush(stderr)

            originalStdout = dup(STDOUT_FILENO)
            originalStderr = dup(STDERR_FILENO)

            guard originalStdout >= 0 && originalStderr >= 0 else {
                isCapturing = false
                return
            }

            let outPipe = Pipe()
            stdoutPipe = outPipe
            let outDup = dup2(outPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
            guard outDup >= 0 else {
                close(originalStdout); originalStdout = -1
                close(originalStderr); originalStderr = -1
                isCapturing = false
                return
            }

            setvbuf(stdout, nil, _IONBF, 0)

            // Use DispatchSource instead of readabilityHandler — more reliable for
            // long-lived pipes. readabilityHandler can silently stop firing on some
            // macOS versions after the initial burst of data.
            let outReadFd = outPipe.fileHandleForReading.fileDescriptor
            fcntl(outReadFd, F_SETFL, fcntl(outReadFd, F_GETFL) | O_NONBLOCK)
            let outSource = DispatchSource.makeReadSource(fileDescriptor: outReadFd, queue: .global(qos: .userInitiated))
            stdoutSource = outSource
            outSource.setEventHandler { [weak self] in
                guard let self = self else { return }
                var allData = Data()
                while true {
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    let bytesRead = read(outReadFd, &buffer, buffer.count)
                    if bytesRead <= 0 { break }
                    allData.append(contentsOf: buffer.prefix(bytesRead))
                }
                guard !allData.isEmpty else { return }
                if self.originalStdout >= 0 {
                    allData.withUnsafeBytes { ptr in
                        if let base = ptr.baseAddress {
                            write(self.originalStdout, base, allData.count)
                        }
                    }
                }
                if let str = String(data: allData, encoding: .utf8) {
                    self.addEntryDirect(str, level: "log")
                }
            }
            outSource.resume()

            let errPipe = Pipe()
            stderrPipe = errPipe
            let errDup = dup2(errPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
            guard errDup >= 0 else {
                dup2(originalStdout, STDOUT_FILENO)
                close(originalStdout); originalStdout = -1
                close(originalStderr); originalStderr = -1
                outSource.cancel()
                stdoutSource = nil
                stdoutPipe = nil
                isCapturing = false
                return
            }

            setvbuf(stderr, nil, _IONBF, 0)

            let errReadFd = errPipe.fileHandleForReading.fileDescriptor
            fcntl(errReadFd, F_SETFL, fcntl(errReadFd, F_GETFL) | O_NONBLOCK)
            let errSource = DispatchSource.makeReadSource(fileDescriptor: errReadFd, queue: .global(qos: .userInitiated))
            stderrSource = errSource
            errSource.setEventHandler { [weak self] in
                guard let self = self else { return }
                var allData = Data()
                while true {
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    let bytesRead = read(errReadFd, &buffer, buffer.count)
                    if bytesRead <= 0 { break }
                    allData.append(contentsOf: buffer.prefix(bytesRead))
                }
                guard !allData.isEmpty else { return }
                if self.originalStderr >= 0 {
                    allData.withUnsafeBytes { ptr in
                        if let base = ptr.baseAddress {
                            write(self.originalStderr, base, allData.count)
                        }
                    }
                }
                if let str = String(data: allData, encoding: .utf8) {
                    self.addEntryDirect(str, level: "error")
                }
            }
            errSource.resume()
            captureOk = true
        }

        if captureOk {
            addDiagnosticEntry()
            verifyCaptureWithSelfTest()
        } else {
            addCaptureFailedEntry()
        }
    }

    /// Writes a test marker directly to fd 1 to verify the pipe actually works.
    /// If the marker doesn't appear in entries within 300ms, adds a warning.
    private func verifyCaptureWithSelfTest() {
        let marker = "appxray-capture-selftest-\(ProcessInfo.processInfo.processIdentifier)"
        let markerLine = marker + "\n"
        if let data = markerLine.data(using: .utf8) {
            // Temporarily ignore SIGPIPE during the test write — if the pipe
            // read end is already closed (race with stopCapture), the write
            // would send SIGPIPE and kill the process.
            let oldHandler = signal(SIGPIPE, SIG_IGN)
            data.withUnsafeBytes { ptr in
                if let base = ptr.baseAddress {
                    write(STDOUT_FILENO, base, data.count)
                }
            }
            signal(SIGPIPE, oldHandler)
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.isCapturing else { return }
            self.entriesLock.lock()
            let found = self.entries.contains { ($0["message"] as? String)?.contains(marker) == true }
            self.entries.removeAll { ($0["message"] as? String)?.contains(marker) == true }
            self.entriesLock.unlock()

            if !found {
                let entry: [String: Any] = [
                    "id": UUID().uuidString,
                    "level": "warn",
                    "message": "stdout pipe self-test failed: print() output may not be captured. The app may use os_log/Logger (bypasses fd capture). Use AppXray.shared.log(_:level:) to bridge those logs.",
                    "timestamp": Date().timeIntervalSince1970 * 1000,
                ]
                self.entriesLock.lock()
                self.entries.insert(entry, at: 0)
                self.entriesLock.unlock()
            }
        }
    }

    /// Adds a diagnostic entry directly (bypassing the prefix filter) so
    /// inspect(target:"logs") is never mysteriously empty.
    private func addDiagnosticEntry() {
        let entry: [String: Any] = [
            "id": UUID().uuidString,
            "level": "debug",
            "message": "Console capture active. print() output is captured automatically. For os_log/Logger output, use AppXray.shared.log(_:level:).",
            "timestamp": Date().timeIntervalSince1970 * 1000,
        ]
        entriesLock.lock()
        entries.insert(entry, at: 0)
        entriesLock.unlock()
    }

    private func addCaptureFailedEntry() {
        let entry: [String: Any] = [
            "id": UUID().uuidString,
            "level": "error",
            "message": "Console capture failed: dup/dup2 returned error. stdout/stderr file descriptors may be unavailable.",
            "timestamp": Date().timeIntervalSince1970 * 1000,
        ]
        entriesLock.lock()
        entries.insert(entry, at: 0)
        entriesLock.unlock()
    }

    func stopCapture() {
        queue.sync {
            guard isCapturing else { return }
            isCapturing = false

            fflush(stdout)
            fflush(stderr)

            // 1. Cancel dispatch sources before touching fds
            stdoutSource?.cancel()
            stderrSource?.cancel()
            stdoutSource = nil
            stderrSource = nil

            // 2. Restore original file descriptors
            if originalStdout >= 0 {
                dup2(originalStdout, STDOUT_FILENO)
                close(originalStdout)
                originalStdout = -1
            }
            if originalStderr >= 0 {
                dup2(originalStderr, STDERR_FILENO)
                close(originalStderr)
                originalStderr = -1
            }

            // 3. Restore line-buffered mode (startCapture sets _IONBF)
            setvbuf(stdout, nil, _IOLBF, 0)
            setvbuf(stderr, nil, _IOLBF, 0)

            // 4. Release pipes (closes both ends)
            stdoutPipe = nil
            stderrPipe = nil
        }
    }

    /// Programmatically log a message (for use by the host app alongside print()).
    /// Use this for messages logged via os_log/Logger which bypass file descriptor capture.
    func log(_ message: String, level: String = "log") {
        addEntryDirect(message, level: level)
    }

    func list(level: String?, limit: Int?, since: TimeInterval?, clear: Bool) -> [[String: Any]] {
        entriesLock.lock()
        defer { entriesLock.unlock() }

        var filtered = entries
        if let level = level {
            filtered = filtered.filter { ($0["level"] as? String) == level }
        }
        if let since = since {
            filtered = filtered.filter { ($0["timestamp"] as? TimeInterval ?? 0) >= since }
        }
        if let limit = limit {
            filtered = Array(filtered.prefix(limit))
        }
        if clear { entries.removeAll() }
        return filtered
    }

    /// Thread-safe entry insertion — called directly from readability handler
    /// background queues without going through the serial queue (avoids contention
    /// with startCapture/stopCapture which hold the serial queue via sync).
    private func addEntryDirect(_ message: String, level: String) {
        let lines = message.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let entryLevel = trimmed.hasPrefix("[appxray]") ? "system" : level

            let entry: [String: Any] = [
                "id": UUID().uuidString,
                "level": entryLevel,
                "message": trimmed,
                "timestamp": Date().timeIntervalSince1970 * 1000,
            ]

            entriesLock.lock()
            entries.insert(entry, at: 0)
            if entries.count > maxEntries {
                entries.removeLast(entries.count - maxEntries)
            }
            entriesLock.unlock()
        }
    }
}

#endif
