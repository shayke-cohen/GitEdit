import Foundation

#if DEBUG

@MainActor
final class WaitEngine {
    private let selectorEngine: SelectorEngine
    private let networkInterceptor: NetworkInterceptor
    private let stateBridge: StateBridge

    init(selectorEngine: SelectorEngine, networkInterceptor: NetworkInterceptor, stateBridge: StateBridge) {
        self.selectorEngine = selectorEngine
        self.networkInterceptor = networkInterceptor
        self.stateBridge = stateBridge
    }

    func waitFor(params: [String: Any]) async -> [String: Any] {
        guard let condition = params["condition"] as? [String: Any],
              let condType = condition["type"] as? String else {
            return ["matched": false, "elapsed": 0, "timedOut": true]
        }

        let timeout = (params["timeout"] as? Int) ?? 10000
        let interval = (params["interval"] as? Int) ?? 200
        let start = Date()

        while Date().timeIntervalSince(start) * 1000 < Double(timeout) {
            let matched = checkCondition(type: condType, condition: condition)
            if matched {
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                return ["matched": true, "elapsed": elapsed, "timedOut": false]
            }
            try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000)
        }

        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        return ["matched": false, "elapsed": elapsed, "timedOut": true]
    }

    private func checkCondition(type: String, condition: [String: Any]) -> Bool {
        switch type {
        case "element":
            let selector = condition["selector"] as? String ?? ""
            let result = selectorEngine.resolve(params: ["selector": selector])
            return result["found"] as? Bool ?? false

        case "gone":
            let selector = condition["selector"] as? String ?? ""
            let result = selectorEngine.resolve(params: ["selector": selector])
            return !(result["found"] as? Bool ?? false)

        case "text":
            let text = condition["text"] as? String ?? ""
            return checkTextVisible(text)

        case "networkIdle":
            return checkNetworkIdle()

        case "state":
            let path = condition["path"] as? String ?? ""
            return checkState(path: path)

        default:
            return false
        }
    }

    private func checkTextVisible(_ text: String) -> Bool {
        let results = selectorEngine.findAll(selector: "@text(\"\(text)\")")
        return !results.isEmpty
    }

    private func checkNetworkIdle() -> Bool {
        let entries = AppXrayURLProtocol.getEntries(filter: nil, limit: nil)
        return entries.allSatisfy { !($0["pending"] as? Bool ?? false) }
    }

    private func checkState(path: String) -> Bool {
        let result = stateBridge.get(path: path, depth: 1)
        return result != nil && result?["error"] == nil
    }
}

#endif
