import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if DEBUG

@MainActor
final class SelectorEngine {

    func resolve(params: [String: Any]) -> [String: Any] {
        guard let selector = params["selector"] as? String, !selector.isEmpty else {
            return ["found": false, "matches": 0]
        }

        let elements = findAll(selector: selector)
        if elements.isEmpty {
            return ["found": false, "matches": 0]
        }

        var result: [String: Any] = [
            "found": true,
            "element": elements[0],
            "matches": elements.count,
        ]
        if elements.count > 1 { result["all"] = elements }
        return result
    }

    func findAll(selector: String) -> [[String: Any]] {
        let parsed = parseSelector(selector)
        switch parsed.type {
        case "text": return findByText(parsed.value)
        case "testId": return findByTestId(parsed.value)
        case "label": return findByLabel(parsed.value)
        case "type": return findByType(parsed.value)
        case "placeholder": return findByPlaceholder(parsed.value)
        case "index":
            guard let idx = parsed.index, let inner = parsed.inner else { return [] }
            let all = findAll(selector: inner)
            return idx < all.count ? [all[idx]] : []
        default: return []
        }
    }

    func resolveCoords(selector: String) -> (x: CGFloat, y: CGFloat)? {
        let elements = findAll(selector: selector)
        #if os(macOS)
        let windowSize = rootWindow?.contentView?.bounds.size
        #endif
        for element in elements {
            guard let bounds = element["bounds"] as? [String: Any],
                  let x = bounds["x"] as? CGFloat,
                  let y = bounds["y"] as? CGFloat,
                  let w = bounds["width"] as? CGFloat,
                  let h = bounds["height"] as? CGFloat,
                  w > 0, h > 0 else { continue }
            #if os(macOS)
            if let ws = windowSize, w >= ws.width * 0.9 && h >= ws.height * 0.9 {
                continue
            }
            #endif
            return (x + w / 2, y + h / 2)
        }
        return nil
    }

    func bestSelector(for view: PlatformView) -> String {
        #if os(iOS)
        if let id = view.accessibilityIdentifier, !id.isEmpty { return "@testId(\"\(id)\")" }
        if let label = view.accessibilityLabel, !label.isEmpty { return "@label(\"\(label)\")" }
        if let btn = view as? UIButton, let title = btn.titleLabel?.text, !title.isEmpty { return "@text(\"\(title)\")" }
        if let lbl = view as? UILabel, let text = lbl.text, !text.isEmpty { return "@text(\"\(text)\")" }
        #elseif os(macOS)
        let id = view.accessibilityIdentifier()
        if !id.isEmpty { return "@testId(\"\(id)\")" }
        let label = view.accessibilityLabel() ?? ""
        if !label.isEmpty { return "@label(\"\(label)\")" }
        if let btn = view as? NSButton, !btn.title.isEmpty { return "@text(\"\(btn.title)\")" }
        if let tf = view as? NSTextField { return "@text(\"\(tf.stringValue)\")" }
        #endif
        return "@type(\"\(String(describing: type(of: view)))\")"
    }

    // MARK: - Finders

    #if os(iOS)
    typealias PlatformView = UIView

    private var rootView: UIView? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    private func findByText(_ text: String) -> [[String: Any]] {
        guard let root = rootView else { return [] }
        var results: [[String: Any]] = []
        walkViews(root) { view in
            if let lbl = view as? UILabel, lbl.text?.localizedCaseInsensitiveContains(text) == true {
                results.append(self.toResolved(view, text: lbl.text))
            } else if let btn = view as? UIButton, btn.titleLabel?.text?.localizedCaseInsensitiveContains(text) == true {
                results.append(self.toResolved(view, text: btn.titleLabel?.text))
            }
        }
        return results
    }

    private func registryToResolved(_ id: String, frame: CGRect) -> [String: Any] {
        return [
            "id": id,
            "type": "XrayRegistered",
            "name": id,
            "bounds": ["x": frame.origin.x, "y": frame.origin.y, "width": frame.width, "height": frame.height],
            "testId": id,
            "text": "" as Any,
            "label": id as Any,
        ]
    }

    private func findByTestId(_ testId: String) -> [[String: Any]] {
        if let frame = XrayViewRegistry.shared.lookup(testId) {
            return [registryToResolved(testId, frame: frame)]
        }
        guard let root = rootView else { return [] }
        var results: [[String: Any]] = []
        walkViews(root) { view in
            if view.accessibilityIdentifier == testId {
                results.append(self.toResolved(view))
            }
        }
        return results
    }

    private func findByLabel(_ label: String) -> [[String: Any]] {
        guard let root = rootView else { return [] }
        var results: [[String: Any]] = []
        walkViews(root) { view in
            if view.accessibilityLabel?.localizedCaseInsensitiveContains(label) == true {
                results.append(self.toResolved(view, label: view.accessibilityLabel))
            }
        }
        return results
    }

    private func findByType(_ typeName: String) -> [[String: Any]] {
        guard let root = rootView else { return [] }
        var results: [[String: Any]] = []
        walkViews(root) { view in
            let viewType = String(describing: type(of: view))
            if viewType.localizedCaseInsensitiveContains(typeName) {
                results.append(self.toResolved(view))
            }
        }
        return results
    }

    private func findByPlaceholder(_ placeholder: String) -> [[String: Any]] {
        guard let root = rootView else { return [] }
        var results: [[String: Any]] = []
        walkViews(root) { view in
            if let tf = view as? UITextField, tf.placeholder?.localizedCaseInsensitiveContains(placeholder) == true {
                results.append(self.toResolved(view, placeholder: tf.placeholder))
            }
        }
        return results
    }

    private func toResolved(_ view: UIView, text: String? = nil, label: String? = nil, placeholder: String? = nil) -> [String: Any] {
        let frame = view.convert(view.bounds, to: nil)
        return [
            "id": "\(ObjectIdentifier(view).hashValue)",
            "type": String(describing: type(of: view)),
            "name": view.accessibilityLabel ?? String(describing: type(of: view)),
            "bounds": ["x": frame.origin.x, "y": frame.origin.y, "width": frame.width, "height": frame.height],
            "text": text as Any,
            "label": (label ?? view.accessibilityLabel) as Any,
            "testId": view.accessibilityIdentifier as Any,
            "placeholder": placeholder as Any,
        ]
    }

    private func walkViews(_ view: UIView, action: (UIView) -> Void) {
        action(view)
        for sub in view.subviews { walkViews(sub, action: action) }
    }

    func findView(selector: String) -> UIView? {
        guard let root = rootView else { return nil }
        let parsed = parseSelector(selector)
        var result: UIView?
        walkViews(root) { view in
            guard result == nil else { return }
            switch parsed.type {
            case "text":
                if let lbl = view as? UILabel, lbl.text?.localizedCaseInsensitiveContains(parsed.value) == true { result = view }
                if let btn = view as? UIButton, btn.titleLabel?.text?.localizedCaseInsensitiveContains(parsed.value) == true { result = view }
            case "testId":
                if view.accessibilityIdentifier == parsed.value { result = view }
            case "label":
                if view.accessibilityLabel?.localizedCaseInsensitiveContains(parsed.value) == true { result = view }
            case "type":
                if String(describing: type(of: view)).localizedCaseInsensitiveContains(parsed.value) { result = view }
            case "placeholder":
                if let tf = view as? UITextField, tf.placeholder?.localizedCaseInsensitiveContains(parsed.value) == true { result = view }
            default: break
            }
        }
        return result
    }

    #elseif os(macOS)
    typealias PlatformView = NSView

    private static let markerPatterns = ["TestID", "TestTag", "MarkerNSView", "AccessibilityNSView"]

    private var rootWindow: NSWindow? {
        ComponentInspector.bestWindow
    }

    private var rootView: NSView? {
        rootWindow?.contentView
    }

    private func findByText(_ text: String) -> [[String: Any]] {
        guard let root = rootView else { return [] }
        var results: [[String: Any]] = []
        var matchedIds = Set<ObjectIdentifier>()

        // Phase 1: Walk the NSView hierarchy for standard controls.
        // Also checks each view's virtual accessibility children — SwiftUI
        // creates non-NSView accessibility elements for Text() views inside
        // hosting containers (CellHostingView, etc.) that have no .stringValue.
        walkAllViews(root) { view in
            let viewId = ObjectIdentifier(view)
            guard !matchedIds.contains(viewId) else { return }

            if let tf = view as? NSTextField, tf.stringValue.localizedCaseInsensitiveContains(text) {
                matchedIds.insert(viewId)
                results.append(self.toResolved(view, text: tf.stringValue))
            } else if let btn = view as? NSButton, btn.title.localizedCaseInsensitiveContains(text) {
                matchedIds.insert(viewId)
                results.append(self.toResolved(view, text: btn.title))
            } else {
                let accessLabel = view.accessibilityLabel() ?? ""
                let accessValue = view.accessibilityValue() as? String ?? ""
                if !accessLabel.isEmpty && accessLabel.localizedCaseInsensitiveContains(text) {
                    matchedIds.insert(viewId)
                    results.append(self.toResolved(view, text: accessLabel))
                } else if !accessValue.isEmpty && accessValue.localizedCaseInsensitiveContains(text) {
                    matchedIds.insert(viewId)
                    results.append(self.toResolved(view, text: accessValue))
                } else if let childText = self.accessibilityChildText(view, matching: text) {
                    matchedIds.insert(viewId)
                    results.append(self.toResolved(view, text: childText))
                }
            }
        }

        return results
    }

    private func registryToResolved(_ id: String, frame: CGRect) -> [String: Any] {
        return [
            "id": id,
            "type": "XrayRegistered",
            "name": id,
            "bounds": ["x": frame.origin.x, "y": frame.origin.y, "width": frame.width, "height": frame.height],
            "testId": id,
            "text": "" as Any,
            "label": id as Any,
        ]
    }

    private func findByTestId(_ testId: String) -> [[String: Any]] {
        if let frame = XrayViewRegistry.shared.lookup(testId) {
            return [registryToResolved(testId, frame: frame)]
        }

        guard let root = rootView else { return [] }
        var results: [[String: Any]] = []
        var matchedIds = Set<ObjectIdentifier>()
        walkAllViews(root) { view in
            if view.accessibilityIdentifier() == testId {
                matchedIds.insert(ObjectIdentifier(view))
                results.append(self.toResolved(view))
            }
        }
        if results.isEmpty, let window = rootWindow {
            walkAccessibilityTree(window) { element, _ in
                let obj = element as AnyObject
                let identifier = obj.accessibilityIdentifier?()
                    ?? (try? (obj as? NSObject)?.value(forKey: "accessibilityIdentifier")) as? String
                if let identifier, identifier == testId {
                    if let view = element as? NSView {
                        let vid = ObjectIdentifier(view)
                        guard !matchedIds.contains(vid) else { return }
                        results.append(self.toResolved(view))
                    } else if let accElem = element as? NSAccessibilityElementProtocol {
                        let text = self.accessibilityText(for: accElem)
                        results.append(self.accessibilityElementToResolved(element, text: text ?? ""))
                    }
                }
            }
        }
        return results
    }

    private func findByLabel(_ label: String) -> [[String: Any]] {
        guard let root = rootView else { return [] }
        var results: [[String: Any]] = []
        var matchedIds = Set<ObjectIdentifier>()
        walkAllViews(root) { view in
            let accessLabel = view.accessibilityLabel() ?? ""
            if accessLabel.localizedCaseInsensitiveContains(label) {
                matchedIds.insert(ObjectIdentifier(view))
                results.append(self.toResolved(view, label: accessLabel))
            }
        }
        if results.isEmpty, let window = rootWindow {
            walkAccessibilityTree(window) { element, _ in
                let obj = element as AnyObject
                if let accessLabel = obj.accessibilityLabel?(),
                   accessLabel.localizedCaseInsensitiveContains(label) {
                    if let view = element as? NSView {
                        let vid = ObjectIdentifier(view)
                        guard !matchedIds.contains(vid) else { return }
                        results.append(self.toResolved(view, label: accessLabel))
                    } else {
                        results.append(self.accessibilityElementToResolved(element, text: accessLabel))
                    }
                }
            }
        }
        return results
    }

    private func findByType(_ typeName: String) -> [[String: Any]] {
        guard let root = rootView else { return [] }
        var results: [[String: Any]] = []
        walkAllViews(root) { view in
            let resolvedType = self.resolvedTypeName(for: view)
            if resolvedType.localizedCaseInsensitiveContains(typeName) {
                results.append(self.toResolved(view))
            }
        }
        return results
    }

    private func findByPlaceholder(_ placeholder: String) -> [[String: Any]] {
        guard let root = rootView else { return [] }
        var results: [[String: Any]] = []
        walkAllViews(root) { view in
            if let tf = view as? NSTextField, (tf.placeholderString ?? "").localizedCaseInsensitiveContains(placeholder) {
                results.append(self.toResolved(view, placeholder: tf.placeholderString))
            }
        }
        return results
    }

    /// Returns the meaningful type name, skipping through marker/overlay views.
    /// Walks up to 5 ancestor levels to find a non-marker type.
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

    /// Returns true if the type name matches a known marker/overlay pattern.
    private func isMarkerType(_ typeName: String) -> Bool {
        for pattern in Self.markerPatterns {
            if typeName.contains(pattern) { return true }
        }
        if typeName.contains("PlatformViewHost") && typeName.contains("Adaptor") { return true }
        return false
    }

    private func toResolved(_ view: NSView, text: String? = nil, label: String? = nil, placeholder: String? = nil) -> [String: Any] {
        var frame = view.convert(view.bounds, to: nil)

        if frame.width <= 0 || frame.height <= 0 {
            let accFrame = view.accessibilityFrame()
            if accFrame.width > 0 && accFrame.height > 0 {
                if let window = view.window {
                    frame = window.convertFromScreen(accFrame)
                } else {
                    frame = accFrame
                }
            }
        }

        if frame.width <= 0 || frame.height <= 0 {
            var current = view.superview
            while let parent = current {
                let parentFrame = parent.convert(parent.bounds, to: nil)
                if parentFrame.width > 0 && parentFrame.height > 0 {
                    frame = parentFrame
                    break
                }
                current = parent.superview
            }
        }

        let windowHeight = view.window?.contentView?.bounds.height ?? frame.origin.y + frame.height
        let flippedY = windowHeight - frame.origin.y - frame.height
        let resolvedType = resolvedTypeName(for: view)

        return [
            "id": "\(ObjectIdentifier(view).hashValue)",
            "type": resolvedType,
            "name": view.accessibilityLabel() ?? resolvedType,
            "bounds": ["x": frame.origin.x, "y": flippedY, "width": frame.width, "height": frame.height],
            "text": text as Any,
            "label": (label ?? view.accessibilityLabel()) as Any,
            "testId": view.accessibilityIdentifier() as Any,
            "placeholder": placeholder as Any,
        ]
    }

    // MARK: - Accessibility Tree

    /// Walk the accessibility tree recursively with safety limits to prevent
    /// hangs from circular references in NSOutlineView/NSTableView proxy objects.
    /// Starts from contentView (not window) to avoid system-level elements.
    private func walkAccessibilityTree(_ root: Any, action: (Any, String) -> Void) {
        var visited = Set<ObjectIdentifier>()
        let deadline = CFAbsoluteTimeGetCurrent() + Self.maxAccessibilityWallTime
        if let window = root as? NSWindow, let contentView = window.contentView {
            walkAccessibilityTreeImpl(contentView, visited: &visited, depth: 0, deadline: deadline, action: action)
        } else {
            walkAccessibilityTreeImpl(root, visited: &visited, depth: 0, deadline: deadline, action: action)
        }
    }

    /// Walk a smaller accessibility subtree rooted at a specific element.
    private func walkAccessibilitySubtree(_ root: Any, action: (Any, String) -> Void) {
        var visited = Set<ObjectIdentifier>()
        let deadline = CFAbsoluteTimeGetCurrent() + Self.maxAccessibilityWallTime
        walkAccessibilityTreeImpl(root, visited: &visited, depth: 0, deadline: deadline, action: action)
    }

    private static let maxAccessibilityDepth = 40
    private static let maxAccessibilityElements = 500
    private static let maxChildrenPerElement = 100
    private static let maxAccessibilityWallTime: CFTimeInterval = 2.0

    private func walkAccessibilityTreeImpl(
        _ root: Any,
        visited: inout Set<ObjectIdentifier>,
        depth: Int,
        deadline: CFAbsoluteTime,
        action: (Any, String) -> Void
    ) {
        guard depth < Self.maxAccessibilityDepth else { return }
        guard visited.count < Self.maxAccessibilityElements else { return }
        guard CFAbsoluteTimeGetCurrent() < deadline else { return }

        let rootObj = root as AnyObject
        let id = ObjectIdentifier(rootObj)
        guard !visited.contains(id) else { return }
        visited.insert(id)

        let obj = root as AnyObject
        if let text = accessibilityTextFromAnyObject(obj), !text.isEmpty {
            action(root, text)
        }

        let children: [Any]?
        if let view = root as? NSView {
            children = view.accessibilityChildren()
        } else if let ns = rootObj as? NSObject,
                  ns.responds(to: NSSelectorFromString("accessibilityChildren")) {
            children = ns.perform(NSSelectorFromString("accessibilityChildren"))?.takeUnretainedValue() as? [Any]
        } else {
            children = nil
        }
        guard let items = children else { return }
        for child in items.prefix(Self.maxChildrenPerElement) {
            walkAccessibilityTreeImpl(child, visited: &visited, depth: depth + 1, deadline: deadline, action: action)
        }
    }

    /// Check a view's non-NSView accessibility children for text, walking up to 4 levels.
    /// SwiftUI creates virtual accessibility elements for Text() views inside hosting
    /// containers (CellHostingView, NSOutlineView rows, etc.). These elements have
    /// AXTitle/AXLabel set but aren't real NSViews. Only walks non-NSView objects
    /// to avoid triggering expensive/blocking NSView.accessibilityChildren() IPC.
    private func accessibilityChildText(_ view: NSView, matching text: String) -> String? {
        guard let children = view.accessibilityChildren() else { return nil }
        var count = 0
        return walkVirtualChildren(children, matching: text, depth: 0, count: &count)
    }

    private static let maxVirtualChildDepth = 4
    private static let maxVirtualChildrenPerLevel = 30
    private static let maxVirtualChildTotal = 200

    /// Recursively walk non-NSView accessibility children (proxy objects, virtual
    /// elements) to extract text. These are safe — unlike NSView.accessibilityChildren(),
    /// virtual elements don't trigger AppKit IPC that can deadlock the main thread.
    private func walkVirtualChildren(_ children: [Any], matching text: String, depth: Int, count: inout Int) -> String? {
        guard depth < Self.maxVirtualChildDepth else { return nil }
        for child in children.prefix(Self.maxVirtualChildrenPerLevel) {
            guard count < Self.maxVirtualChildTotal else { return nil }
            if child is NSView { continue }
            count += 1
            if let childText = accessibilityTextFromAnyObject(child as AnyObject),
               childText.localizedCaseInsensitiveContains(text) {
                return childText
            }
            let obj = child as AnyObject
            if let ns = obj as? NSObject, ns.responds(to: NSSelectorFromString("accessibilityChildren")),
               let grandchildren = ns.perform(NSSelectorFromString("accessibilityChildren"))?.takeUnretainedValue() as? [Any] {
                if let found = walkVirtualChildren(grandchildren, matching: text, depth: depth + 1, count: &count) {
                    return found
                }
            }
        }
        return nil
    }

    /// Extract text from any object that responds to accessibility selectors.
    /// Uses AnyObject dispatch to avoid protocol conformance requirements,
    /// which fail at runtime for NSAccessibilityElement.
    private func accessibilityTextFromAnyObject(_ obj: AnyObject) -> String? {
        if let title = obj.accessibilityTitle?(), !title.isEmpty { return title }
        if let label = obj.accessibilityLabel?(), !label.isEmpty { return label }
        if let val = (try? (obj as? NSObject)?.value(forKey: "accessibilityValue")) as? String, !val.isEmpty { return val }
        return nil
    }

    /// Extract text from an accessibility element by checking role-appropriate properties.
    private func accessibilityText(for element: NSAccessibilityElementProtocol) -> String? {
        let obj = element as AnyObject

        // AXTitle covers buttons, menu items, toolbar items, and static text
        if let title = obj.accessibilityTitle?(), !title.isEmpty { return title }
        // AXLabel is the accessibility label
        if let label = obj.accessibilityLabel?(), !label.isEmpty { return label }
        // AXValue — use KVC to avoid ambiguity across NSAccessibility protocol variants
        if let val = (try? (obj as? NSObject)?.value(forKey: "accessibilityValue")) as? String, !val.isEmpty { return val }

        return nil
    }

    /// Create a resolved element dict from a non-NSView accessibility element.
    private func accessibilityElementToResolved(_ element: Any, text: String) -> [String: Any] {
        let obj = element as AnyObject
        var frame = CGRect.zero
        if obj.responds(to: #selector(NSAccessibilityElementProtocol.accessibilityFrame)) {
            frame = obj.accessibilityFrame?() ?? .zero
        }
        if !frame.isEmpty, let window = rootWindow {
            frame = window.convertFromScreen(frame)
            let windowHeight = window.contentView?.bounds.height ?? frame.origin.y + frame.height
            let flippedY = windowHeight - frame.origin.y - frame.height
            frame.origin.y = flippedY
        }

        let label = obj.accessibilityLabel?() ?? text
        return [
            "id": "\(ObjectIdentifier(obj).hashValue)",
            "type": "Text",
            "name": label,
            "bounds": ["x": frame.origin.x, "y": frame.origin.y, "width": frame.width, "height": frame.height],
            "text": text,
            "label": label as Any,
            "testId": NSNull() as Any,
            "placeholder": NSNull() as Any,
        ]
    }

    /// Walk all views including NSOutlineView/NSTableView row views and toolbar items.
    private func walkAllViews(_ root: NSView, action: (NSView) -> Void) {
        walkViews(root, action: action)
        // Also walk toolbar item views which live outside contentView
        if let toolbar = rootWindow?.toolbar {
            for item in toolbar.items {
                if let itemView = item.view {
                    walkViews(itemView, action: action)
                }
            }
        }
    }

    private func walkViews(_ view: NSView, action: (NSView) -> Void) {
        action(view)
        // NSOutlineView / NSTableView: also walk visible row views which may not
        // be in the standard subviews array during lazy cell reuse.
        if let tableView = view as? NSTableView {
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            for row in visibleRows.location..<(visibleRows.location + visibleRows.length) {
                if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) {
                    walkViews(rowView, action: action)
                }
            }
            return
        }
        for sub in view.subviews { walkViews(sub, action: action) }
    }

    func findView(selector: String) -> NSView? {
        guard let root = rootView else { return nil }
        let parsed = parseSelector(selector)
        var result: NSView?
        walkAllViews(root) { view in
            guard result == nil else { return }
            switch parsed.type {
            case "text":
                if let tf = view as? NSTextField, tf.stringValue.localizedCaseInsensitiveContains(parsed.value) { result = view }
                else if let btn = view as? NSButton, btn.title.localizedCaseInsensitiveContains(parsed.value) { result = view }
                else if (view.accessibilityLabel() ?? "").localizedCaseInsensitiveContains(parsed.value) { result = view }
                else if let val = view.accessibilityValue() as? String, val.localizedCaseInsensitiveContains(parsed.value) { result = view }
                else if self.accessibilityChildText(view, matching: parsed.value) != nil { result = view }
            case "testId":
                if view.accessibilityIdentifier() == parsed.value { result = view }
            case "label":
                if (view.accessibilityLabel() ?? "").localizedCaseInsensitiveContains(parsed.value) { result = view }
            case "type":
                if self.resolvedTypeName(for: view).localizedCaseInsensitiveContains(parsed.value) { result = view }
            case "placeholder":
                if let tf = view as? NSTextField, (tf.placeholderString ?? "").localizedCaseInsensitiveContains(parsed.value) { result = view }
            default: break
            }
        }

        return result
    }

    /// Find the nearest NSView ancestor for a non-view accessibility element.
    private func nearestView(for element: Any, depth: Int = 0) -> NSView? {
        guard depth < 20 else { return rootView }
        let obj = element as AnyObject
        if let parent = obj.accessibilityParent?() {
            if let view = parent as? NSView { return view }
            return nearestView(for: parent, depth: depth + 1)
        }
        return rootView
    }
    #endif

    // MARK: - Selector parser

    private struct ParsedSelector {
        let type: String
        let value: String
        let index: Int?
        let inner: String?
    }

    private func parseSelector(_ raw: String) -> ParsedSelector {
        let pattern = #"^@(\w+)\("([^"]*)"\)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
            let typeRange = Range(match.range(at: 1), in: raw)!
            let valueRange = Range(match.range(at: 2), in: raw)!
            return ParsedSelector(type: String(raw[typeRange]), value: String(raw[valueRange]), index: nil, inner: nil)
        }

        let indexPattern = #"^@index\((\d+),\s*(.+)\)$"#
        if let regex = try? NSRegularExpression(pattern: indexPattern),
           let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
            let idxRange = Range(match.range(at: 1), in: raw)!
            let innerRange = Range(match.range(at: 2), in: raw)!
            return ParsedSelector(type: "index", value: "", index: Int(raw[idxRange]), inner: String(raw[innerRange]))
        }

        return ParsedSelector(type: "unknown", value: raw, index: nil, inner: nil)
    }
}

#endif
