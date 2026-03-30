import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class ComponentInspector {
    private var nodeCounter = 0

    #if os(macOS)
    /// Prefer keyWindow, then the first visible window, then any window.
    static var bestWindow: NSWindow? {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first(where: { $0.isVisible })
            ?? NSApplication.shared.windows.first
    }

    /// All visible windows, ordered so the key window comes first.
    /// Includes sheet windows and child windows that macOS SwiftUI presents
    /// as separate NSWindow instances.
    static var allVisibleWindows: [NSWindow] {
        let all = NSApplication.shared.windows.filter { $0.isVisible }
        guard let key = NSApplication.shared.keyWindow else { return all }
        return [key] + all.filter { $0 !== key }
    }
    #endif

    func getTree(params: [String: Any]) -> [String: Any] {
        let depth = params["depth"] as? Int
        let componentId = params["componentId"] as? String
        let includeHandlers = params["includeHandlers"] as? Bool ?? true
        let filter = params["filter"] as? String
        let root = buildTree(depth: depth, filter: filter, includeHandlers: includeHandlers)
        if let id = componentId, !id.isEmpty {
            if let node = findNode(root, id: id) {
                return serializeNode(node)
            }
            return ["error": "Component not found"]
        }
        return serializeNode(root)
    }

    func triggerHandler(params: [String: Any]) -> [String: Any] {
        let componentId = params["componentId"] as? String
        let componentName = params["componentName"] as? String
        let handler = params["handler"] as? String ?? ""
        guard !handler.isEmpty else { return ["success": false, "error": "handler required"] }

        #if os(iOS)
        if let window = keyWindow {
            if findAndTrigger(in: window, componentId: componentId, componentName: componentName, handler: handler) {
                return ["success": true]
            }
        }
        #elseif os(macOS)
        for window in Self.allVisibleWindows {
            if findAndTrigger(in: window.contentView, componentId: componentId, componentName: componentName, handler: handler) {
                return ["success": true]
            }
        }
        #endif
        return ["success": false, "error": "Handler not found"]
    }

    func input(params: [String: Any]) -> [String: Any] {
        let componentId = params["componentId"] as? String
        let selector = params["selector"] as? String
        let value = params["value"] as? String ?? ""

        #if os(iOS)
        if let window = keyWindow,
           let field = findInputField(in: window, componentId: componentId, selector: selector) {
            if let tf = field as? UITextField {
                tf.text = value
                tf.sendActions(for: .editingChanged)
            } else if let tv = field as? UITextView {
                tv.text = value
            }
            return ["success": true]
        }
        #elseif os(macOS)
        for window in Self.allVisibleWindows {
            if let field = findInputField(in: window.contentView, componentId: componentId, selector: selector) as? NSTextField {
                field.stringValue = value
                return ["success": true]
            }
        }
        #endif
        return ["success": false, "error": "Input field not found"]
    }

    #if os(iOS)
    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    private func buildTree(depth: Int?, filter: String?, includeHandlers: Bool) -> ComponentNode {
        nodeCounter = 0
        guard let window = keyWindow else {
            return ComponentNode(id: "root", type: "Root", name: "Root", children: [], depth: 0, isVisible: true, handlers: [])
        }
        let rootView = (window.rootViewController?.view) ?? window
        return buildNode(from: rootView, depth: 0, maxDepth: depth, filter: filter, includeHandlers: includeHandlers)
    }

    private func buildNode(from view: UIView, depth: Int, maxDepth: Int?, filter: String?, includeHandlers: Bool) -> ComponentNode {
        nodeCounter += 1
        let id = "n\(nodeCounter)"
        let typeName = String(describing: type(of: view))
        let label = view.accessibilityLabel ?? ""
        let frame = view.bounds
        let rect: [String: Any] = ["x": frame.origin.x, "y": frame.origin.y, "width": frame.width, "height": frame.height]
        let isVisible = !view.isHidden && view.alpha > 0
        var handlers: [[String: Any]] = []
        if includeHandlers, view is UIControl {
            handlers = [["name": "tap", "paramTypes": [] as [String]]]
        }
        if let f = filter, !f.isEmpty {
            let match = typeName.localizedCaseInsensitiveContains(f) || label.localizedCaseInsensitiveContains(f)
            if !match {
                return ComponentNode(id: id, type: typeName, name: label, children: [], depth: depth, isVisible: isVisible, handlers: handlers, bounds: rect, accessibilityLabel: label)
            }
        }
        var children: [ComponentNode] = []
        if maxDepth == nil || depth < maxDepth! {
            for subview in view.subviews {
                children.append(buildNode(from: subview, depth: depth + 1, maxDepth: maxDepth, filter: filter, includeHandlers: includeHandlers))
            }
        }
        return ComponentNode(id: id, type: typeName, name: label, children: children, depth: depth, isVisible: isVisible, handlers: handlers, bounds: rect, accessibilityLabel: label)
    }

    private func findAndTrigger(in view: UIView, componentId: String?, componentName: String?, handler: String) -> Bool {
        if let control = view as? UIControl {
            control.sendActions(for: .touchUpInside)
            return true
        }
        for subview in view.subviews {
            if findAndTrigger(in: subview, componentId: componentId, componentName: componentName, handler: handler) {
                return true
            }
        }
        return false
    }

    private func findInputField(in view: UIView, componentId: String?, selector: String?) -> UIView? {
        if view is UITextField || view is UITextView { return view }
        for subview in view.subviews {
            if let found = findInputField(in: subview, componentId: componentId, selector: selector) { return found }
        }
        return nil
    }
    #elseif os(macOS)
    private static let markerPatterns = ["TestID", "TestTag", "MarkerNSView", "AccessibilityNSView"]
    private static let hostingPatterns = ["NSHostingView", "NSHostingController"]

    private static let maxTreeDepth = 80
    private static let maxTreeElements = 5000
    private static let maxTreeWallTime: CFTimeInterval = 8.0

    private static let maxAccTreeDepth = 40
    private static let maxAccTreeElements = 500
    private static let maxAccTreeChildren = 100
    private static let maxAccTreeWallTime: CFTimeInterval = 2.0

    private struct TreeWalkContext {
        var elementCount = 0
        var deadline: CFAbsoluteTime
        var visited = Set<ObjectIdentifier>()

        var isExhausted: Bool {
            elementCount >= ComponentInspector.maxTreeElements
                || CFAbsoluteTimeGetCurrent() >= deadline
        }
    }

    private func resolvedTypeName(for view: NSView) -> String {
        let typeName = String(describing: type(of: view))
        guard isMarkerType(typeName) else { return typeName }
        var current: NSView? = view.superview
        var depth = 0
        while let parent = current, depth < 5 {
            let parentType = String(describing: type(of: parent))
            if !isMarkerType(parentType) { return parentType }
            current = parent.superview
            depth += 1
        }
        return typeName
    }

    private func isMarkerType(_ typeName: String) -> Bool {
        for pattern in Self.markerPatterns {
            if typeName.contains(pattern) { return true }
        }
        if typeName.contains("PlatformViewHost") && typeName.contains("Adaptor") { return true }
        return false
    }

    private func isSwiftUIHostingBoundary(_ view: NSView) -> Bool {
        let typeName = String(describing: type(of: view))
        for pattern in Self.hostingPatterns {
            if typeName.contains(pattern) { return true }
        }
        if typeName.contains("_NSHostingView") { return true }
        let subs = view.subviews
        if subs.count > 0 && subs.allSatisfy({ isMarkerType(String(describing: type(of: $0))) }) {
            return true
        }
        return false
    }

    private func buildTree(depth: Int?, filter: String?, includeHandlers: Bool) -> ComponentNode {
        nodeCounter = 0
        let windows = Self.allVisibleWindows
        guard !windows.isEmpty else {
            return ComponentNode(id: "root", type: "Root", name: "Root", children: [], depth: 0, isVisible: true, handlers: [])
        }

        var ctx = TreeWalkContext(deadline: CFAbsoluteTimeGetCurrent() + Self.maxTreeWallTime)
        var rootChildren: [ComponentNode] = []
        for window in windows {
            guard let contentView = window.contentView else { continue }
            guard !ctx.isExhausted else { break }
            var windowChildren = [buildNode(from: contentView, depth: 2, maxDepth: depth, filter: filter, includeHandlers: includeHandlers, ctx: &ctx)]

            if let toolbar = window.toolbar, (depth == nil || depth! > 2), !ctx.isExhausted {
                for item in toolbar.items {
                    guard !ctx.isExhausted else { break }
                    if let itemView = item.view {
                        windowChildren.append(buildNode(from: itemView, depth: 2, maxDepth: depth, filter: filter, includeHandlers: includeHandlers, ctx: &ctx))
                    }
                }
            }

            let windowNode = ComponentNode(
                id: "w\(nodeCounter + 1)", type: "Window", name: window.title,
                children: windowChildren, depth: 1, isVisible: true, handlers: [],
                bounds: nil, accessibilityLabel: window.title
            )
            nodeCounter += 1
            rootChildren.append(windowNode)
        }

        let title = windows.first?.title ?? ""
        return ComponentNode(id: "root", type: "Application", name: title, children: rootChildren, depth: 0, isVisible: true, handlers: [], bounds: nil, accessibilityLabel: title)
    }

    private func buildNode(from view: NSView, depth: Int, maxDepth: Int?, filter: String?, includeHandlers: Bool, ctx: inout TreeWalkContext) -> ComponentNode {
        if ctx.isExhausted || depth > Self.maxTreeDepth || Task.isCancelled {
            return ComponentNode(id: "t\(nodeCounter)", type: "Truncated", name: "...", children: [], depth: depth, isVisible: true, handlers: [],
                                 bounds: nil, accessibilityLabel: nil)
        }

        ctx.elementCount += 1
        nodeCounter += 1
        let id = "n\(nodeCounter)"
        let typeName = resolvedTypeName(for: view)
        let label = view.accessibilityLabel() ?? ""
        let frame = view.bounds
        let rect: [String: Any] = ["x": frame.origin.x, "y": frame.origin.y, "width": frame.width, "height": frame.height]
        let isVisible = !view.isHidden
        var handlers: [[String: Any]] = []
        if includeHandlers, let control = view as? NSControl, control.action != nil {
            handlers = [["name": control.action!.description, "paramTypes": [] as [String]]]
        }
        if let f = filter, !f.isEmpty {
            let match = typeName.localizedCaseInsensitiveContains(f) || label.localizedCaseInsensitiveContains(f)
            if !match {
                return ComponentNode(id: id, type: typeName, name: label, children: [], depth: depth, isVisible: isVisible, handlers: handlers, bounds: rect, accessibilityLabel: label)
            }
        }
        var children: [ComponentNode] = []
        if maxDepth == nil || depth < maxDepth! {
            if isSwiftUIHostingBoundary(view) {
                children = buildAccessibilityChildren(of: view, depth: depth + 1, maxDepth: maxDepth, filter: filter, includeHandlers: includeHandlers)
            } else if let tableView = view as? NSTableView {
                let visibleRows = tableView.rows(in: tableView.visibleRect)
                for row in visibleRows.location..<(visibleRows.location + visibleRows.length) {
                    guard !ctx.isExhausted else { break }
                    if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) {
                        children.append(buildNode(from: rowView, depth: depth + 1, maxDepth: maxDepth, filter: filter, includeHandlers: includeHandlers, ctx: &ctx))
                    }
                }
            } else {
                for subview in view.subviews {
                    guard !ctx.isExhausted else { break }
                    appendFlatteningMarkers(subview, into: &children, depth: depth + 1, maxDepth: maxDepth, filter: filter, includeHandlers: includeHandlers, ctx: &ctx)
                }
            }
        }
        return ComponentNode(id: id, type: typeName, name: label, children: children, depth: depth, isVisible: isVisible, handlers: handlers, bounds: rect, accessibilityLabel: label)
    }

    /// Build tree nodes from the accessibility hierarchy instead of NSView.subviews.
    /// Used for SwiftUI hosting boundaries where the accessibility tree is the
    /// semantic representation (Button, Text, TextField) rather than internal bridging views.
    private func buildAccessibilityChildren(of view: NSView, depth: Int, maxDepth: Int?, filter: String?, includeHandlers: Bool) -> [ComponentNode] {
        guard let accChildren = view.accessibilityChildren() else { return [] }
        var results: [ComponentNode] = []
        var visited = Set<ObjectIdentifier>()
        let deadline = CFAbsoluteTimeGetCurrent() + Self.maxAccTreeWallTime
        buildAccNodes(from: accChildren, into: &results, visited: &visited,
                      depth: depth, maxDepth: maxDepth, filter: filter,
                      includeHandlers: includeHandlers, deadline: deadline)
        return results
    }

    private func buildAccNodes(
        from elements: [Any], into results: inout [ComponentNode],
        visited: inout Set<ObjectIdentifier>, depth: Int, maxDepth: Int?,
        filter: String?, includeHandlers: Bool, deadline: CFAbsoluteTime
    ) {
        guard depth < Self.maxAccTreeDepth else { return }
        guard visited.count < Self.maxAccTreeElements else { return }
        guard CFAbsoluteTimeGetCurrent() < deadline else { return }
        guard !Task.isCancelled else { return }

        for element in elements.prefix(Self.maxAccTreeChildren) {
            guard visited.count < Self.maxAccTreeElements else { return }
            guard CFAbsoluteTimeGetCurrent() < deadline else { return }

            let obj = element as AnyObject
            let oid = ObjectIdentifier(obj)
            guard !visited.contains(oid) else { continue }
            visited.insert(oid)

            if let nsView = element as? NSView {
                let typeName = resolvedTypeName(for: nsView)
                if isMarkerType(String(describing: type(of: nsView))) {
                    if let grandchildren = nsView.accessibilityChildren() {
                        buildAccNodes(from: grandchildren, into: &results, visited: &visited,
                                      depth: depth, maxDepth: maxDepth, filter: filter,
                                      includeHandlers: includeHandlers, deadline: deadline)
                    }
                    continue
                }
                nodeCounter += 1
                let id = "n\(nodeCounter)"
                let label = nsView.accessibilityLabel() ?? ""
                let frame = nsView.bounds
                let rect: [String: Any] = ["x": frame.origin.x, "y": frame.origin.y, "width": frame.width, "height": frame.height]
                results.append(ComponentNode(id: id, type: typeName, name: label, children: [], depth: depth, isVisible: !nsView.isHidden, handlers: [], bounds: rect, accessibilityLabel: label))
                continue
            }

            let role = (obj.accessibilityRole?() as? NSAccessibility.Role)?.rawValue ?? "Unknown"
            let title = obj.accessibilityTitle?() ?? ""
            let label = obj.accessibilityLabel?() ?? title
            let testId = obj.accessibilityIdentifier?()
                ?? (try? (obj as? NSObject)?.value(forKey: "accessibilityIdentifier")) as? String
                ?? ""
            var accFrame = CGRect.zero
            if obj.responds(to: #selector(NSAccessibilityElementProtocol.accessibilityFrame)) {
                accFrame = obj.accessibilityFrame?() ?? .zero
            }
            let rect: [String: Any] = ["x": accFrame.origin.x, "y": accFrame.origin.y, "width": accFrame.width, "height": accFrame.height]

            nodeCounter += 1
            let nodeId = "n\(nodeCounter)"
            let name = !label.isEmpty ? label : role
            if let f = filter, !f.isEmpty {
                if !role.localizedCaseInsensitiveContains(f) && !name.localizedCaseInsensitiveContains(f) {
                    continue
                }
            }

            var children: [ComponentNode] = []
            if maxDepth == nil || depth < maxDepth! {
                let grandchildren: [Any]?
                if let ns = obj as? NSObject, ns.responds(to: NSSelectorFromString("accessibilityChildren")) {
                    grandchildren = ns.perform(NSSelectorFromString("accessibilityChildren"))?.takeUnretainedValue() as? [Any]
                } else {
                    grandchildren = nil
                }
                if let gc = grandchildren {
                    buildAccNodes(from: gc, into: &children, visited: &visited,
                                  depth: depth + 1, maxDepth: maxDepth, filter: filter,
                                  includeHandlers: includeHandlers, deadline: deadline)
                }
            }

            var node = ComponentNode(id: nodeId, type: role, name: name, children: children, depth: depth, isVisible: true, handlers: [], bounds: rect, accessibilityLabel: label.isEmpty ? nil : label)
            if !testId.isEmpty {
                node.props["testId"] = testId
            }
            results.append(node)
        }
    }

    private func appendFlatteningMarkers(_ subview: NSView, into children: inout [ComponentNode], depth: Int, maxDepth: Int?, filter: String?, includeHandlers: Bool, ctx: inout TreeWalkContext) {
        guard !ctx.isExhausted && !Task.isCancelled else { return }
        let rawType = String(describing: type(of: subview))
        if isMarkerType(rawType) {
            for grandchild in subview.subviews {
                guard !ctx.isExhausted else { return }
                appendFlatteningMarkers(grandchild, into: &children, depth: depth, maxDepth: maxDepth, filter: filter, includeHandlers: includeHandlers, ctx: &ctx)
            }
        } else {
            children.append(buildNode(from: subview, depth: depth, maxDepth: maxDepth, filter: filter, includeHandlers: includeHandlers, ctx: &ctx))
        }
    }

    private func findAndTrigger(in view: NSView?, componentId: String?, componentName: String?, handler: String) -> Bool {
        guard let view = view else { return false }
        if let control = view as? NSControl, control.action != nil {
            NSApp.sendAction(control.action!, to: control.target, from: control)
            return true
        }
        for subview in view.subviews {
            if findAndTrigger(in: subview, componentId: componentId, componentName: componentName, handler: handler) { return true }
        }
        return false
    }

    private func findInputField(in view: NSView?, componentId: String?, selector: String?) -> NSView? {
        guard let view = view else { return nil }
        if view is NSTextField { return view }
        for subview in view.subviews {
            if let found = findInputField(in: subview, componentId: componentId, selector: selector) { return found }
        }
        return nil
    }
    #endif

    private func findNode(_ node: ComponentNode, id: String) -> ComponentNode? {
        if node.id == id { return node }
        for child in node.children {
            if let found = findNode(child, id: id) { return found }
        }
        return nil
    }

    private func serializeNode(_ node: ComponentNode) -> [String: Any] {
        var dict: [String: Any] = [
            "id": node.id, "type": node.type, "name": node.name, "depth": node.depth,
            "isVisible": node.isVisible, "props": node.props, "state": node.state,
            "handlers": node.handlers, "children": node.children.map { serializeNode($0) },
        ]
        if let b = node.bounds { dict["bounds"] = b }
        if let l = node.accessibilityLabel { dict["accessibilityLabel"] = l }
        return dict
    }
}

private struct ComponentNode {
    let id: String
    let type: String
    let name: String
    var props: [String: Any]
    var state: [String: Any]
    var handlers: [[String: Any]]
    let children: [ComponentNode]
    let depth: Int
    let isVisible: Bool
    var bounds: [String: Any]?
    var accessibilityLabel: String?

    init(id: String, type: String, name: String, children: [ComponentNode], depth: Int, isVisible: Bool, handlers: [[String: Any]], bounds: [String: Any]? = nil, accessibilityLabel: String? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.props = [:]
        self.state = [:]
        self.handlers = handlers
        self.children = children
        self.depth = depth
        self.isVisible = isVisible
        self.bounds = bounds
        self.accessibilityLabel = accessibilityLabel
    }
}
