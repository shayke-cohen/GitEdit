import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if DEBUG

// MARK: - ChaosEngine

/// Chaos injection: network errors, delays, memory pressure, etc.
final class ChaosEngine: @unchecked Sendable {
    private let networkInterceptor: NetworkInterceptor
    private let queue = DispatchQueue(label: "com.appxray.chaos", qos: .userInitiated)
    private var activeRules: [String: ChaosRule] = [:]

    init(networkInterceptor: NetworkInterceptor) {
        self.networkInterceptor = networkInterceptor
    }

    func start(params: [String: Any]) async -> [String: Any] {
        let config = params["config"] as? [String: Any] ?? params
        let type = config["type"] as? String ?? "network-error"
        let target = config["target"] as? String
        let duration = config["duration"] as? Int ?? 5000
        _ = config["probability"] as? Double

        let id = UUID().uuidString

        switch type {
        case "network-error", "network-slow", "network-timeout":
            let rule = ChaosRule(
                id: id,
                type: type,
                target: target,
                duration: duration,
                active: true
            )
            AppXrayURLProtocol.addChaosRule(rule)
            queue.sync { activeRules[id] = rule }
            return ["id": id, "type": type, "active": true] as [String: Any]

        case "memory-pressure":
            #if os(iOS)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
            }
            #endif
            return ["id": id, "type": type, "active": true, "fired": true] as [String: Any]

        case "cpu-spike":
            DispatchQueue.global(qos: .userInitiated).async {
                let end = Date().addingTimeInterval(TimeInterval(duration) / 1000.0)
                while Date() < end {
                    _ = (0..<1000000).reduce(0, +)
                }
            }
            return ["id": id, "type": type, "active": true] as [String: Any]

        default:
            return ["success": false, "error": "Unknown chaos type: \(type)"]
        }
    }

    func stop(params: [String: Any]) async -> [String: Any] {
        let id = params["id"] as? String

        if let id = id {
            AppXrayURLProtocol.removeChaosRule(id: id)
            queue.sync { _ = activeRules.removeValue(forKey: id) }
            return ["success": true, "stopped": id] as [String: Any]
        }
        AppXrayURLProtocol.clearChaosRules()
        queue.sync { activeRules.removeAll() }
        return ["success": true, "stopped": "all"] as [String: Any]
    }

    func list() -> [String: Any] {
        let rules = AppXrayURLProtocol.listChaosRules()
        return ["rules": rules]
    }
}

#endif
