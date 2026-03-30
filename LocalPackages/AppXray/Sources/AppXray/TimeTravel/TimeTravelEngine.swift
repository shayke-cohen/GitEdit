import Foundation

#if DEBUG

// MARK: - TimeTravelEngine

/// Checkpoint and restore for state time-travel.
final class TimeTravelEngine: @unchecked Sendable {
    private let stateBridge: StateBridge
    private let navigationBridge: NavigationBridge
    private let queue = DispatchQueue(label: "com.appxray.timetravel", qos: .userInitiated)
    private var checkpoints: [Checkpoint] = []
    private var history: [HistoryEntry] = []
    private let maxCheckpoints = 50
    private let maxHistory = 200

    struct Checkpoint {
        let id: String
        let name: String
        let timestamp: TimeInterval
        let stateSnapshot: [String: Any]
        let navigationState: [String: Any]
        let description: String?
    }

    struct HistoryEntry {
        let index: Int
        let path: String
        let oldValue: Any?
        let newValue: Any?
        let timestamp: TimeInterval
        let checkpointBefore: String?
    }

    init(stateBridge: StateBridge, navigationBridge: NavigationBridge) {
        self.stateBridge = stateBridge
        self.navigationBridge = navigationBridge
    }

    func createCheckpoint(params: [String: Any]) async -> [String: Any] {
        let name = params["name"] as? String ?? "checkpoint-\(Int(Date().timeIntervalSince1970))"
        let description = params["description"] as? String

        let id = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        let stateSnapshot = stateBridge.snapshot()
        let navigationState = await MainActor.run { navigationBridge.getState() }

        let checkpoint = Checkpoint(
            id: id,
            name: name,
            timestamp: timestamp,
            stateSnapshot: stateSnapshot,
            navigationState: navigationState,
            description: description
        )

        queue.sync {
            checkpoints.insert(checkpoint, at: 0)
            if checkpoints.count > maxCheckpoints {
                checkpoints = Array(checkpoints.prefix(maxCheckpoints))
            }
        }

        return [
            "id": id,
            "name": name,
            "timestamp": Int(timestamp * 1000),
            "description": description as Any,
        ] as [String: Any]
    }

    func restoreCheckpoint(params: [String: Any]) async -> [String: Any] {
        let name = params["name"] as? String
        let checkpointId = params["checkpointId"] as? String

        let checkpoint: Checkpoint? = queue.sync {
            if let id = checkpointId {
                return checkpoints.first { $0.id == id }
            }
            if let n = name {
                return checkpoints.first { $0.name == n }
            }
            return checkpoints.first
        }

        guard let cp = checkpoint else {
            return ["success": false, "error": "Checkpoint not found"]
        }

        stateBridge.restore(cp.stateSnapshot)
        // Navigation restore would need the binding to support replace/reset
        return [
            "success": true,
            "checkpointId": cp.id,
            "name": cp.name,
        ] as [String: Any]
    }

    func getHistory(params: [String: Any]) async -> [String: Any] {
        let limit = params["limit"] as? Int
        let since = params["since"] as? TimeInterval
        let path = params["path"] as? String

        let entries: [[String: Any]] = queue.sync {
            var result = history
            if let s = since {
                result = result.filter { $0.timestamp >= s }
            }
            if let p = path, !p.isEmpty {
                result = result.filter { ($0.path).hasPrefix(p) }
            }
            if let lim = limit {
                result = Array(result.prefix(lim))
            }
            return result.map { e in
                [
                    "index": e.index,
                    "path": e.path,
                    "oldValue": e.oldValue as Any,
                    "newValue": e.newValue as Any,
                    "timestamp": Int(e.timestamp * 1000),
                    "checkpointBefore": e.checkpointBefore as Any,
                ] as [String: Any]
            }
        }
        return ["history": entries]
    }

    func recordMutation(path: String, oldValue: Any?, newValue: Any?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let entry = HistoryEntry(
                index: self.history.count,
                path: path,
                oldValue: oldValue,
                newValue: newValue,
                timestamp: Date().timeIntervalSince1970,
                checkpointBefore: self.checkpoints.first?.id
            )
            self.history.insert(entry, at: 0)
            if self.history.count > self.maxHistory {
                self.history = Array(self.history.prefix(self.maxHistory))
            }
        }
    }
}

#endif
