import Foundation

#if DEBUG

/// Thread-safe buffer of captured errors for inspection via errors.list.
final class ErrorBuffer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.appxray.errorbuffer", qos: .userInitiated)
    private var entries: [[String: Any]] = []
    private let maxEntries = 100
    private weak var timeline: TimelineBridge?

    init(timeline: TimelineBridge? = nil) {
        self.timeline = timeline
    }

    func capture(_ error: Error, context: String?) {
        queue.sync {
            let errorType = (error as NSError).domain
            let message = error.localizedDescription
            timeline?.emit(category: .error, action: errorType, summary: message)

            let entry: [String: Any] = [
                "id": UUID().uuidString,
                "type": "caught",
                "message": error.localizedDescription,
                "stack": Thread.callStackSymbols.joined(separator: "\n"),
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "metadata": [
                    "context": context as Any,
                    "domain": (error as NSError).domain,
                    "code": (error as NSError).code,
                ] as [String: Any],
            ]
            entries.insert(entry, at: 0)
            if entries.count > maxEntries {
                entries = Array(entries.prefix(maxEntries))
            }
        }
    }

    func list(type: String?, limit: Int?, since: TimeInterval?, clear: Bool) -> [[String: Any]] {
        queue.sync {
            var result = entries

            if let t = type {
                result = result.filter { ($0["type"] as? String) == t }
            }
            if let s = since {
                let sinceMs = Int(s * 1000)
                result = result.filter { ($0["timestamp"] as? Int ?? 0) >= sinceMs }
            }
            if let l = limit {
                result = Array(result.prefix(l))
            }
            if clear {
                entries.removeAll()
            }
            return result
        }
    }
}

#endif
