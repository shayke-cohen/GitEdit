import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if DEBUG

@MainActor
final class InteractionEngine {
    private let selectorEngine: SelectorEngine

    init(selectorEngine: SelectorEngine) {
        self.selectorEngine = selectorEngine
    }

    func tap(params: [String: Any]) async -> [String: Any] {
        #if os(macOS)
        // For selector-based taps on macOS, try direct accessibilityPerformPress
        // first. This avoids coordinate-based clicking which can hit phantom
        // accessibility elements (window-sized bounds) and block the main actor.
        if let selector = params["selector"] as? String {
            if let view = selectorEngine.findView(selector: selector) {
                if view.accessibilityPerformPress() {
                    await Task.yield()
                    return ["success": true, "action": "tap", "selector": selector]
                }
                // Try walking up to find a pressable ancestor (buttons, table rows, etc.)
                var current = view.superview
                var depth = 0
                while let ancestor = current, depth < 10 {
                    if ancestor.accessibilityPerformPress() {
                        await Task.yield()
                        return ["success": true, "action": "tap", "selector": selector]
                    }
                    // For NSTableRowView, use native row selection instead
                    if let rowView = ancestor as? NSTableRowView,
                       let tableView = findAncestorTableView(of: rowView) {
                        let row = tableView.row(for: rowView)
                        if row >= 0 {
                            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                            if let action = tableView.action {
                                NSApp.sendAction(action, to: tableView.target, from: tableView)
                            }
                            await Task.yield()
                            return ["success": true, "action": "tap", "selector": selector]
                        }
                    }
                    current = ancestor.superview
                    depth += 1
                }
                // Coordinate-based fallback for views with valid bounds.
                // Use findTableViewRow path but skip synthetic NSApp.sendEvent
                // (which can block the main actor when no event loop is running).
                let frame = view.convert(view.bounds, to: nil)
                if frame.width > 0 && frame.height > 0,
                   let window = view.window, let contentView = window.contentView {
                    let contentHeight = contentView.bounds.height
                    let windowCoord = NSPoint(x: frame.midX, y: contentHeight - frame.midY)
                    if let hitView = contentView.hitTest(windowCoord) {
                        if let (tableView, row) = findTableViewRow(containing: hitView) {
                            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                            if let action = tableView.action {
                                NSApp.sendAction(action, to: tableView.target, from: tableView)
                            }
                            await Task.yield()
                            return ["success": true, "action": "tap", "selector": selector]
                        }
                    }
                }
                // Found element but no press method worked.
                // Return gracefully instead of falling through to clickAtPoint
                // (which uses NSApp.sendEvent and can block the main actor).
                await Task.yield()
                return ["success": false, "action": "tap", "error": "Element found but not pressable via accessibility", "selector": selector]
            }
        }
        #endif

        guard let (x, y) = resolveCoords(params) else {
            return ["success": false, "action": "tap", "error": "Cannot resolve coordinates"]
        }
        let count = params["count"] as? Int ?? 1

        #if os(iOS)
        for _ in 0..<count {
            tapAtPoint(CGPoint(x: x, y: y))
        }
        #elseif os(macOS)
        for _ in 0..<count {
            clickAtPoint(CGPoint(x: x, y: y))
        }
        #endif

        await Task.yield()
        return ["success": true, "action": "tap", "coordinates": ["x": x, "y": y]]
    }

    func longPress(params: [String: Any]) async -> [String: Any] {
        guard let (x, y) = resolveCoords(params) else {
            return ["success": false, "action": "longPress", "error": "Cannot resolve coordinates"]
        }
        let duration = (params["duration"] as? Double) ?? 500.0

        #if os(iOS)
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }),
              let view = window.hitTest(CGPoint(x: x, y: y), with: nil) else {
            return ["success": false, "action": "longPress", "error": "No view at point"]
        }
        if let longPressGR = view.gestureRecognizers?.first(where: { $0 is UILongPressGestureRecognizer }) {
            longPressGR.state = .began
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000))
            longPressGR.state = .ended
        }
        #elseif os(macOS)
        guard let window = ComponentInspector.bestWindow,
              let contentView = window.contentView else {
            return ["success": false, "action": "longPress", "error": "No window"]
        }
        let windowCoord = NSPoint(x: x, y: contentView.bounds.height - y)
        if let event = NSEvent.mouseEvent(with: .leftMouseDown, location: windowCoord, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0) {
            NSApp.sendEvent(event)
        }
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000))
        if let event = NSEvent.mouseEvent(with: .leftMouseUp, location: windowCoord, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
            NSApp.sendEvent(event)
        }
        #endif

        return ["success": true, "action": "longPress", "coordinates": ["x": x, "y": y], "duration": duration]
    }

    func typeText(params: [String: Any]) async -> [String: Any] {
        guard let text = params["text"] as? String else {
            return ["success": false, "action": "type", "error": "text required"]
        }
        let clearFirst = params["clearFirst"] as? Bool ?? false

        #if os(iOS)
        var target: UIView?
        if let selector = params["selector"] as? String {
            target = selectorEngine.findView(selector: selector)
        } else {
            target = UIResponder.currentFirstResponder as? UIView
        }
        guard let inputView = target else {
            return ["success": false, "action": "type", "error": "No input target"]
        }

        if let tf = inputView as? UITextField {
            tf.becomeFirstResponder()
            if clearFirst { tf.text = "" }
            tf.insertText(text)
            tf.sendActions(for: .editingChanged)
        } else if let tv = inputView as? UITextView {
            tv.becomeFirstResponder()
            if clearFirst { tv.text = "" }
            tv.insertText(text)
        } else {
            return ["success": false, "action": "type", "error": "Not a text input"]
        }
        #elseif os(macOS)
        var target: NSView?
        if let selector = params["selector"] as? String {
            target = selectorEngine.findView(selector: selector)
        }
        guard let inputView = target as? NSTextField else {
            return ["success": false, "action": "type", "error": "No NSTextField target"]
        }
        inputView.becomeFirstResponder()
        if clearFirst { inputView.stringValue = "" }
        inputView.stringValue += text
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: inputView)
        #endif

        return ["success": true, "action": "type"]
    }

    func swipe(params: [String: Any]) async -> [String: Any] {
        let direction = params["direction"] as? String ?? "up"
        let distance = (params["distance"] as? CGFloat) ?? 300
        let startX: CGFloat
        let startY: CGFloat

        if let coords = resolveCoords(params) {
            startX = coords.0
            startY = coords.1
        } else {
            #if os(iOS)
            let size = UIScreen.main.bounds.size
            #elseif os(macOS)
            let size = NSScreen.main?.frame.size ?? CGSize(width: 1024, height: 768)
            #endif
            startX = size.width / 2
            startY = size.height / 2
        }

        let (dx, dy) = swipeDelta(direction: direction, distance: distance)

        #if os(iOS)
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }),
              let scrollView = findScrollView(in: window, at: CGPoint(x: startX, y: startY)) else {
            return ["success": false, "action": "swipe", "error": "No scrollable view found"]
        }
        let offset = scrollView.contentOffset
        scrollView.setContentOffset(CGPoint(x: offset.x - dx, y: offset.y - dy), animated: true)
        #elseif os(macOS)
        guard let window = ComponentInspector.bestWindow,
              let contentView = window.contentView else {
            return ["success": false, "action": "swipe", "error": "No window"]
        }

        let flipped = NSPoint(x: startX, y: contentView.bounds.height - startY)
        if let scrollView = findScrollView(in: contentView, at: flipped) {
            let clip = scrollView.contentView
            let origin = clip.bounds.origin
            let newOrigin = NSPoint(x: origin.x - dx, y: origin.y - dy)
            scrollView.contentView.scroll(to: newOrigin)
            scrollView.reflectScrolledClipView(clip)
        } else {
            let point = CGPoint(x: startX, y: startY)
            let steps = 5
            let stepDy = Int32(dy / CGFloat(steps))
            let stepDx = Int32(dx / CGFloat(steps))
            for _ in 0..<steps {
                if let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                         wheelCount: 2, wheel1: stepDy, wheel2: stepDx, wheel3: 0) {
                    cgEvent.location = point
                    if let nsEvent = NSEvent(cgEvent: cgEvent) {
                        NSApp.sendEvent(nsEvent)
                    }
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
        #endif

        return ["success": true, "action": "swipe", "coordinates": ["x": startX, "y": startY]]
    }

    func drag(params: [String: Any]) async -> [String: Any] {
        guard let fromCoords = resolveCoords(["selector": params["fromSelector"], "x": params["fromX"], "y": params["fromY"]]),
              let toCoords = resolveCoords(["selector": params["toSelector"], "x": params["toX"], "y": params["toY"]]) else {
            return ["success": false, "action": "drag", "error": "Cannot resolve drag coordinates"]
        }

        return ["success": true, "action": "drag",
                "from": ["x": fromCoords.0, "y": fromCoords.1],
                "to": ["x": toCoords.0, "y": toCoords.1]]
    }

    // MARK: - Helpers

    private func resolveCoords(_ params: [String: Any]) -> (CGFloat, CGFloat)? {
        if let x = params["x"] as? CGFloat, let y = params["y"] as? CGFloat { return (x, y) }
        if let x = params["x"] as? Double, let y = params["y"] as? Double { return (CGFloat(x), CGFloat(y)) }
        if let selector = params["selector"] as? String {
            return selectorEngine.resolveCoords(selector: selector)
        }
        return nil
    }

    #if os(iOS)
    private func tapAtPoint(_ point: CGPoint) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }),
              let view = window.hitTest(point, with: nil) else { return }

        if let control = view as? UIControl {
            control.sendActions(for: .touchUpInside)
            return
        }

        if let tapGR = view.gestureRecognizers?.first(where: { $0 is UITapGestureRecognizer }) {
            tapGR.state = .ended
            return
        }

        if view.accessibilityActivate() { return }

        var current: UIView? = view.superview
        while let parent = current {
            if let control = parent as? UIControl {
                control.sendActions(for: .touchUpInside)
                return
            }
            if parent.accessibilityActivate() { return }
            if let tapGR = parent.gestureRecognizers?.first(where: { $0 is UITapGestureRecognizer }) {
                tapGR.state = .ended
                return
            }
            current = parent.superview
        }
    }

    private func findScrollView(in view: UIView, at point: CGPoint) -> UIScrollView? {
        if let sv = view as? UIScrollView, sv.frame.contains(point) { return sv }
        for sub in view.subviews.reversed() {
            if let found = findScrollView(in: sub, at: point) { return found }
        }
        return nil
    }
    #elseif os(macOS)
    /// Accepts top-left origin coordinates (matching protocol/screenshot convention).
    /// Converts to AppKit's bottom-left origin internally.
    private func clickAtPoint(_ point: CGPoint) {
        guard let window = ComponentInspector.bestWindow,
              let contentView = window.contentView else { return }

        let windowCoord = NSPoint(x: point.x, y: contentView.bounds.height - point.y)

        if let hitView = contentView.hitTest(windowCoord) {
            // NSOutlineView / NSTableView: use native row selection API instead of
            // synthetic events, which don't trigger SwiftUI List(selection:) bindings.
            if let (tableView, row) = findTableViewRow(containing: hitView) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                if let action = tableView.action {
                    NSApp.sendAction(action, to: tableView.target, from: tableView)
                }
                return
            }

            var current: NSView? = hitView
            while let view = current {
                if view.accessibilityPerformPress() { return }
                current = view.superview
            }
        }

        // Also check toolbar items — they live outside contentView
        if let toolbar = window.toolbar {
            for item in toolbar.items {
                guard let itemView = item.view else { continue }
                let itemFrame = itemView.convert(itemView.bounds, to: nil)
                let flippedItemY = (window.contentView?.bounds.height ?? 0) - itemFrame.origin.y - itemFrame.height
                let itemRect = CGRect(x: itemFrame.origin.x, y: flippedItemY, width: itemFrame.width, height: itemFrame.height)
                if itemRect.contains(point) {
                    if itemView.accessibilityPerformPress() { return }
                    if let control = itemView as? NSControl, let action = control.action {
                        NSApp.sendAction(action, to: control.target, from: control)
                        return
                    }
                }
            }
        }

        if let down = NSEvent.mouseEvent(with: .leftMouseDown, location: windowCoord, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0),
           let up = NSEvent.mouseEvent(with: .leftMouseUp, location: windowCoord, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
            NSApp.sendEvent(down)
            NSApp.sendEvent(up)
        }
    }

    /// Walk up from a hit view to find its enclosing NSOutlineView/NSTableView and the row index.
    private func findTableViewRow(containing view: NSView) -> (NSTableView, Int)? {
        var current: NSView? = view
        while let v = current {
            if let rowView = v as? NSTableRowView {
                if let tableView = rowView.superview as? NSTableView ?? findAncestorTableView(of: rowView) {
                    let row = tableView.row(for: rowView)
                    if row >= 0 { return (tableView, row) }
                }
            }
            current = v.superview
        }
        return nil
    }

    private func findAncestorTableView(of view: NSView) -> NSTableView? {
        var current: NSView? = view.superview
        while let v = current {
            if let tv = v as? NSTableView { return tv }
            current = v.superview
        }
        return nil
    }

    private func findScrollView(in view: NSView, at point: NSPoint) -> NSScrollView? {
        for sub in view.subviews.reversed() {
            let local = sub.convert(point, from: view)
            if sub.bounds.contains(local) {
                if let found = findScrollView(in: sub, at: local) { return found }
            }
        }
        if let sv = view as? NSScrollView { return sv }
        return nil
    }
    #endif

    private func swipeDelta(direction: String, distance: CGFloat) -> (CGFloat, CGFloat) {
        switch direction {
        case "up": return (0, -distance)
        case "down": return (0, distance)
        case "left": return (-distance, 0)
        case "right": return (distance, 0)
        default: return (0, -distance)
        }
    }
}

#if os(iOS)
private extension UIResponder {
    private weak static var _currentFirstResponder: UIResponder?
    static var currentFirstResponder: UIResponder? {
        _currentFirstResponder = nil
        UIApplication.shared.sendAction(#selector(findFirstResponder(_:)), to: nil, from: nil, for: nil)
        return _currentFirstResponder
    }
    @objc private func findFirstResponder(_ sender: Any?) {
        UIResponder._currentFirstResponder = self
    }
}
#endif

#endif
