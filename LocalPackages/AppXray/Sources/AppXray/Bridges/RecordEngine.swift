import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if DEBUG

@MainActor
final class RecordEngine {
    private let selectorEngine: SelectorEngine
    private var recording = false
    private var actions: [[String: Any]] = []
    private var startedAt: TimeInterval = 0

    init(selectorEngine: SelectorEngine) {
        self.selectorEngine = selectorEngine
    }

    func start() -> [String: Any] {
        guard !recording else { return ["started": false] }
        recording = true
        actions = []
        startedAt = Date().timeIntervalSince1970 * 1000
        installHooks()
        return ["started": true]
    }

    func stop() -> [String: Any] {
        recording = false
        removeHooks()
        let duration = Date().timeIntervalSince1970 * 1000 - startedAt
        return [
            "actions": actions,
            "duration": Int(duration),
            "startedAt": Int(startedAt),
        ]
    }

    func getEvents(params: [String: Any]) -> [String: Any] {
        let limit = params["limit"] as? Int ?? 100
        let slice = actions.suffix(limit)
        return ["actions": Array(slice), "recording": recording]
    }

    func recordAction(action: String, selector: String?, coords: CGPoint?, text: String? = nil, value: Any? = nil) {
        guard recording else { return }
        var entry: [String: Any] = [
            "action": action,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ]
        if let sel = selector { entry["selector"] = sel }
        if let c = coords { entry["coords"] = ["x": c.x, "y": c.y] }
        if let t = text { entry["text"] = t }
        if let v = value { entry["value"] = v }
        actions.append(entry)
    }

    private func installHooks() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textFieldDidChange(_:)),
            name: UITextField.textDidChangeNotification,
            object: nil
        )
        #elseif os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textFieldDidChange(_:)),
            name: NSControl.textDidChangeNotification,
            object: nil
        )
        #endif
    }

    private func removeHooks() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func textFieldDidChange(_ notification: Notification) {
        guard recording else { return }
        #if os(iOS)
        if let tf = notification.object as? UITextField {
            let selector = selectorEngine.bestSelector(for: tf)
            recordAction(action: "type", selector: selector, coords: nil, text: tf.text)
        }
        #elseif os(macOS)
        if let tf = notification.object as? NSTextField {
            let selector = selectorEngine.bestSelector(for: tf)
            recordAction(action: "type", selector: selector, coords: nil, text: tf.stringValue)
        }
        #endif
    }
}

#endif
