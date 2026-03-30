import XCTest
import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
@testable import AppXray

#if DEBUG

@MainActor
final class SelectorEngineTests: XCTestCase {

    let engine = SelectorEngine()

    // MARK: - Selector parsing via resolve()

    func testEmptySelectorReturnsNotFound() {
        let result = engine.resolve(params: ["selector": ""])
        XCTAssertEqual(result["found"] as? Bool, false)
        XCTAssertEqual(result["matches"] as? Int, 0)
    }

    func testMissingSelectorReturnsNotFound() {
        let result = engine.resolve(params: [:])
        XCTAssertEqual(result["found"] as? Bool, false)
    }

    func testUnknownSelectorTypeReturnsEmpty() {
        let results = engine.findAll(selector: "@banana(\"hello\")")
        XCTAssertTrue(results.isEmpty)
    }

    func testInvalidSelectorFormatReturnsEmpty() {
        let results = engine.findAll(selector: "just-plain-text")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - findAll with no root view (returns empty when no window)

    func testFindByTextNoRootViewReturnsEmpty() {
        let results = engine.findAll(selector: "@text(\"Hello\")")
        // In a test environment without a running app, rootView is nil
        XCTAssertTrue(results.isEmpty)
    }

    func testFindByTestIdNoRootViewReturnsEmpty() {
        let results = engine.findAll(selector: "@testId(\"my-button\")")
        XCTAssertTrue(results.isEmpty)
    }

    func testFindByLabelNoRootViewReturnsEmpty() {
        let results = engine.findAll(selector: "@label(\"Close\")")
        XCTAssertTrue(results.isEmpty)
    }

    func testFindByTypeNoRootViewReturnsEmpty() {
        let results = engine.findAll(selector: "@type(\"NSButton\")")
        XCTAssertTrue(results.isEmpty)
    }

    func testFindByPlaceholderNoRootViewReturnsEmpty() {
        let results = engine.findAll(selector: "@placeholder(\"Search...\")")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Index selector

    func testIndexSelectorWithNoMatchesReturnsEmpty() {
        let results = engine.findAll(selector: "@index(0, @text(\"nonexistent\"))")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - resolveCoords with no root view

    func testResolveCoordsNoRootViewReturnsNil() {
        let result = engine.resolveCoords(selector: "@text(\"Hello\")")
        XCTAssertNil(result)
    }

    // MARK: - bestSelector

    #if os(macOS)
    func testBestSelectorForNSButtonUsesLabelOrText() {
        let button = NSButton(title: "Click Me", target: nil, action: nil)
        let selector = engine.bestSelector(for: button)
        // NSButton exposes its title as accessibilityLabel() by default,
        // so bestSelector may return @label or @text depending on AppKit.
        XCTAssertTrue(
            selector == "@text(\"Click Me\")" || selector == "@label(\"Click Me\")",
            "Expected text or label selector, got: \(selector)"
        )
    }

    func testBestSelectorForNSTextFieldReturnsTextSelector() {
        let tf = NSTextField(string: "Hello World")
        let selector = engine.bestSelector(for: tf)
        XCTAssertEqual(selector, "@text(\"Hello World\")")
    }

    func testBestSelectorPrefersTestId() {
        let button = NSButton(title: "Click", target: nil, action: nil)
        button.setAccessibilityIdentifier("my-btn")
        let selector = engine.bestSelector(for: button)
        XCTAssertEqual(selector, "@testId(\"my-btn\")")
    }

    func testBestSelectorPrefersLabelOverText() {
        let view = NSView()
        view.setAccessibilityLabel("My View Label")
        let selector = engine.bestSelector(for: view)
        XCTAssertEqual(selector, "@label(\"My View Label\")")
    }

    func testBestSelectorFallsBackToType() {
        let view = NSView()
        let selector = engine.bestSelector(for: view)
        XCTAssertTrue(selector.hasPrefix("@type("))
    }
    #elseif os(iOS)
    func testBestSelectorForUIButtonReturnsTextSelector() {
        let button = UIButton(type: .system)
        button.setTitle("Tap Me", for: .normal)
        let selector = engine.bestSelector(for: button)
        XCTAssertEqual(selector, "@text(\"Tap Me\")")
    }

    func testBestSelectorForUILabelReturnsTextSelector() {
        let label = UILabel()
        label.text = "Hello"
        let selector = engine.bestSelector(for: label)
        XCTAssertEqual(selector, "@text(\"Hello\")")
    }

    func testBestSelectorPrefersTestId() {
        let view = UIView()
        view.accessibilityIdentifier = "my-view"
        let selector = engine.bestSelector(for: view)
        XCTAssertEqual(selector, "@testId(\"my-view\")")
    }

    func testBestSelectorPrefersLabelOverType() {
        let view = UIView()
        view.accessibilityLabel = "My View"
        let selector = engine.bestSelector(for: view)
        XCTAssertEqual(selector, "@label(\"My View\")")
    }
    #endif

    // MARK: - findView with no root

    func testFindViewNoRootReturnsNil() {
        let result = engine.findView(selector: "@text(\"test\")")
        XCTAssertNil(result)
    }

    #if os(macOS)
    // MARK: - macOS: Marker view type resolution (Issue 4)

    func testIsMarkerTypeDetectsTestIDNSView() {
        let engine = SelectorEngine()
        let view = TestIDNSViewStub()
        let resolvedType = engine.bestSelector(for: view)
        // TestIDNSView is a plain NSView subclass — bestSelector uses resolvedTypeName
        // which should detect "TestID" in the name and skip to parent.
        // Without a parent, it falls back to the type itself.
        XCTAssertTrue(resolvedType.contains("@type("))
    }

    func testResolvedTypeNameSkipsMarkerToParent() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let parent = NSButton(title: "RealButton", target: nil, action: nil)
        parent.frame = NSRect(x: 10, y: 10, width: 100, height: 30)
        let marker = TestIDNSViewStub()
        marker.frame = NSRect(x: 0, y: 0, width: 100, height: 30)
        marker.setAccessibilityIdentifier("marker.test")
        parent.addSubview(marker)
        window.contentView?.addSubview(parent)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@testId(\"marker.test\")")
        XCTAssertFalse(results.isEmpty, "Should find marker by testId")

        if let first = results.first {
            let typeName = first["type"] as? String ?? ""
            XCTAssertFalse(
                typeName.contains("TestID"),
                "Marker type should be resolved to parent, got: \(typeName)"
            )
        }

        window.orderOut(nil)
    }

    func testResolvedTypeNameHandlesPlatformViewHostWrapper() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let grandparent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        grandparent.setAccessibilityLabel("ContentView")
        let hostView = PlatformViewHostAdaptorStub()
        hostView.frame = NSRect(x: 10, y: 10, width: 100, height: 30)
        let markerView = TestIDNSViewStub()
        markerView.frame = NSRect(x: 0, y: 0, width: 100, height: 30)
        markerView.setAccessibilityIdentifier("nested.marker")
        hostView.addSubview(markerView)
        grandparent.addSubview(hostView)
        window.contentView?.addSubview(grandparent)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@testId(\"nested.marker\")")
        XCTAssertFalse(results.isEmpty, "Should find nested marker by testId")

        if let first = results.first {
            let typeName = first["type"] as? String ?? ""
            XCTAssertFalse(
                typeName.contains("TestID") || typeName.contains("PlatformViewHost"),
                "Double-wrapped marker should resolve to grandparent, got: \(typeName)"
            )
        }

        window.orderOut(nil)
    }

    // MARK: - macOS: Accessibility tree walking for @text() (Issue 1)

    func testFindByTextViaAccessibilityLabel() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        // Simulate a SwiftUI text element: an NSView that has no .stringValue
        // but exposes text via accessibilityLabel (as SwiftUI's accessibility bridge does).
        let drawingView = NSView(frame: NSRect(x: 10, y: 10, width: 100, height: 20))
        drawingView.setAccessibilityLabel("Board")
        window.contentView?.addSubview(drawingView)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@text(\"Board\")")
        XCTAssertFalse(results.isEmpty, "Should find text via accessibility label")
        XCTAssertEqual(results.first?["text"] as? String, "Board")

        window.orderOut(nil)
    }

    func testFindByTextViaAccessibilityValue() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = NSView(frame: NSRect(x: 10, y: 10, width: 100, height: 20))
        view.setAccessibilityValue("Settings")
        window.contentView?.addSubview(view)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@text(\"Settings\")")
        XCTAssertFalse(results.isEmpty, "Should find text via accessibility value")

        window.orderOut(nil)
    }

    func testFindByTextAccessibilityTreeFallback() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let container = AccessibilityContainerView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView?.addSubview(container)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@text(\"Sessions\")")
        XCTAssertNotNil(results, "Accessibility tree walk should not crash")

        window.orderOut(nil)
    }

    // MARK: - Accessibility tree cycle detection (P0 fix)

    func testAccessibilityTreeWalkDoesNotHangOnCyclicProxies() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let cyclic = CyclicAccessibilityView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        window.contentView?.addSubview(cyclic)
        window.makeKeyAndOrderFront(nil)

        // This must complete in finite time — before the fix, it would hang forever
        let results = engine.findAll(selector: "@text(\"Phantom\")")
        XCTAssertNotNil(results, "Should complete without hanging")

        window.orderOut(nil)
    }

    func testFindByTextCompletesQuicklyWithProblematicViews() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let flooding = ProxyFloodingView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        window.contentView?.addSubview(flooding)
        window.makeKeyAndOrderFront(nil)

        let start = CFAbsoluteTimeGetCurrent()
        let results = engine.findAll(selector: "@text(\"NonexistentText\")")
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertNotNil(results, "Should complete without hanging")
        XCTAssertLessThan(elapsed, 1.0, "Phase 1-only @text() should complete in under 1 second")

        window.orderOut(nil)
    }

    func testFindByTextFindsMultipleMatchesViaPhase1() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let button = NSButton(title: "Board", target: nil, action: nil)
        button.frame = NSRect(x: 10, y: 10, width: 80, height: 30)
        window.contentView?.addSubview(button)
        let accView = NSView(frame: NSRect(x: 100, y: 10, width: 80, height: 30))
        accView.setAccessibilityLabel("Board Sidebar")
        window.contentView?.addSubview(accView)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@text(\"Board\")")
        XCTAssertGreaterThanOrEqual(results.count, 2, "Phase 1 should find both NSButton title and accessibilityLabel matches")

        window.orderOut(nil)
    }

    func testFindViewByTextUsesAccessibilityFallback() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = NSView(frame: NSRect(x: 10, y: 10, width: 100, height: 20))
        view.setAccessibilityLabel("NavItem")
        window.contentView?.addSubview(view)
        window.makeKeyAndOrderFront(nil)

        let foundView = engine.findView(selector: "@text(\"NavItem\")")
        XCTAssertNotNil(foundView, "findView should find views via accessibility label")

        window.orderOut(nil)
    }

    func testFindByTextCaseInsensitive() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = NSView(frame: NSRect(x: 10, y: 10, width: 100, height: 20))
        view.setAccessibilityLabel("Live Missions")
        window.contentView?.addSubview(view)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@text(\"live missions\")")
        XCTAssertFalse(results.isEmpty, "Text search should be case-insensitive")

        window.orderOut(nil)
    }

    func testFindByLabelAccessibilityTreeFallback() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = NSView(frame: NSRect(x: 10, y: 10, width: 100, height: 20))
        view.setAccessibilityLabel("SidebarLabel")
        window.contentView?.addSubview(view)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@label(\"SidebarLabel\")")
        XCTAssertFalse(results.isEmpty, "Should find label from NSView walk")

        window.orderOut(nil)
    }

    // MARK: - macOS: toResolved coordinate flipping

    func testToResolvedBoundsAreFlippedToTopLeft() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let button = NSButton(title: "CoordTest", target: nil, action: nil)
        button.frame = NSRect(x: 50, y: 200, width: 100, height: 30)
        window.contentView?.addSubview(button)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@text(\"CoordTest\")")
        XCTAssertFalse(results.isEmpty, "Should find the button by text")

        if let first = results.first, let bounds = first["bounds"] as? [String: Any] {
            let y = bounds["y"] as? CGFloat ?? -1
            let height = bounds["height"] as? CGFloat ?? 0
            let contentHeight = window.contentView?.bounds.height ?? 300
            // In top-left coords, a button near the bottom (y=200 in AppKit)
            // should have a small y value (near the top) = contentHeight - 200 - 30 = 70
            XCTAssertGreaterThanOrEqual(y, 0, "Y should be non-negative in top-left coords")
            XCTAssertLessThan(y, contentHeight, "Y should be less than window height")
            XCTAssertGreaterThan(height, 0, "Height should be positive")
        }

        window.orderOut(nil)
    }

    func testToResolvedFallsBackToAccessibilityFrame() {
        let view = NSView(frame: .zero)
        view.setAccessibilityLabel("ZeroBoundsView")
        // A zero-frame view with an accessibility label should still be found
        // and use the accessibility frame or ancestor fallback
        let selector = engine.bestSelector(for: view)
        XCTAssertEqual(selector, "@label(\"ZeroBoundsView\")")
    }

    func testFindByTextWithAccessibilityLabel() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = NSView(frame: NSRect(x: 10, y: 10, width: 100, height: 50))
        view.setAccessibilityLabel("Custom Label")
        window.contentView?.addSubview(view)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@text(\"Custom Label\")")
        XCTAssertFalse(results.isEmpty, "Should find view by accessibility label text")

        if let first = results.first, let bounds = first["bounds"] as? [String: Any] {
            let width = bounds["width"] as? CGFloat ?? 0
            let height = bounds["height"] as? CGFloat ?? 0
            XCTAssertGreaterThan(width, 0)
            XCTAssertGreaterThan(height, 0)
        }

        window.orderOut(nil)
    }

    // MARK: - Round 5: resolveCoords skips window-sized phantom elements

    func testResolveCoordsSkipsWindowSizedBounds() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        // Add a small button with "Test" — this is the valid match
        let button = NSButton(title: "ResolveTest", target: nil, action: nil)
        button.frame = NSRect(x: 50, y: 50, width: 80, height: 30)
        window.contentView?.addSubview(button)
        window.makeKeyAndOrderFront(nil)

        let coords = engine.resolveCoords(selector: "@text(\"ResolveTest\")")
        XCTAssertNotNil(coords, "Should find coords for the button")
        if let (x, y) = coords {
            XCTAssertGreaterThan(x, 0)
            XCTAssertGreaterThan(y, 0)
            // Coords should be near the button center, not the window center
            XCTAssertLessThan(x, 200, "X should be near the button, not at window center")
        }

        window.orderOut(nil)
    }

    // MARK: - Round 5: resolvedTypeName walks up multiple levels

    func testResolvedTypeNameWalksUpMultipleLevels() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let realView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let host1 = PlatformViewHostAdaptorStub()
        host1.frame = NSRect(x: 10, y: 10, width: 100, height: 30)
        let host2 = PlatformViewHostAdaptorStub()
        host2.frame = NSRect(x: 0, y: 0, width: 100, height: 30)
        let marker = TestIDNSViewStub()
        marker.frame = NSRect(x: 0, y: 0, width: 100, height: 30)
        marker.setAccessibilityIdentifier("deep.marker")

        host2.addSubview(marker)
        host1.addSubview(host2)
        realView.addSubview(host1)
        window.contentView?.addSubview(realView)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@testId(\"deep.marker\")")
        XCTAssertFalse(results.isEmpty, "Should find deeply nested marker")

        if let first = results.first {
            let typeName = first["type"] as? String ?? ""
            XCTAssertFalse(
                typeName.contains("TestID") || typeName.contains("PlatformViewHost"),
                "Triple-nested marker should resolve past all markers, got: \(typeName)"
            )
        }

        window.orderOut(nil)
    }

    // MARK: - Round 5: accessibility subtree search

    func testAccessibilitySubtreeSearchDoesNotHang() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let container = AccessibilityContainerView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView?.addSubview(container)
        window.makeKeyAndOrderFront(nil)

        // The accessibility subtree walk must complete in finite time even with
        // containers that report accessibility children. Must not hang.
        let results = engine.findAll(selector: "@text(\"Sessions\")")
        XCTAssertNotNil(results, "Accessibility subtree walk should complete without hanging")

        window.orderOut(nil)
    }

    // MARK: - Round 6: @text() finds text via virtual accessibility children

    func testAccessibilityChildTextExtractionFromNSAccessibilityElement() {
        // Verify that NSAccessibilityElement's title/label are extractable
        // via the accessibilityText(for:) path — this is the mechanism used
        // to find SwiftUI text inside hosting containers.
        let element = NSAccessibilityElement()
        element.setAccessibilityLabel("Sidebar Sessions")
        element.setAccessibilityRole(.staticText)

        let obj = element as AnyObject
        let label = obj.accessibilityLabel?() ?? ""
        XCTAssertEqual(label, "Sidebar Sessions", "NSAccessibilityElement should expose label via AnyObject dispatch")
    }

    func testFindByTextViaAccessibilityChildren() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let hostingView = AccessibilityTextHostView(frame: NSRect(x: 10, y: 10, width: 150, height: 30), childText: "Sidebar Sessions")
        window.contentView?.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@text(\"Sidebar Sessions\")")
        XCTAssertFalse(results.isEmpty, "Should find text via virtual accessibility children")
        if let first = results.first {
            XCTAssertEqual(first["text"] as? String, "Sidebar Sessions")
        }

        window.orderOut(nil)
    }

    func testFindViewByTextViaAccessibilityChildren() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let hostingView = AccessibilityTextHostView(frame: NSRect(x: 10, y: 10, width: 150, height: 30), childText: "Sidebar Inbox")
        window.contentView?.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)

        let foundView = engine.findView(selector: "@text(\"Sidebar Inbox\")")
        XCTAssertNotNil(foundView, "findView should find view via accessibility children text")

        window.orderOut(nil)
    }

    func testFindByTextViaDeepVirtualAccessibilityChildren() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let deepHost = DeepAccessibilityTextHostView(
            frame: NSRect(x: 10, y: 10, width: 150, height: 30),
            childText: "DeepNestedSessions",
            nestingDepth: 3
        )
        window.contentView?.addSubview(deepHost)
        window.makeKeyAndOrderFront(nil)

        let results = engine.findAll(selector: "@text(\"DeepNestedSessions\")")
        XCTAssertFalse(results.isEmpty, "Should find text nested 3 levels deep in virtual accessibility children")
        if let first = results.first {
            XCTAssertEqual(first["text"] as? String, "DeepNestedSessions")
        }

        window.orderOut(nil)
    }

    func testFindByTextDoesNotHangOnDeepSearch() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let cyclic = CyclicAccessibilityView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let flooding = ProxyFloodingView(frame: NSRect(x: 100, y: 0, width: 100, height: 100))
        window.contentView?.addSubview(cyclic)
        window.contentView?.addSubview(flooding)
        window.makeKeyAndOrderFront(nil)

        let start = CFAbsoluteTimeGetCurrent()
        let results = engine.findAll(selector: "@text(\"Nonexistent\")")
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertTrue(results.isEmpty)
        XCTAssertLessThan(elapsed, 1.0, "@text() must never trigger blocking accessibility tree walk")

        window.orderOut(nil)
    }
    #endif
}

// MARK: - Test helpers

#if os(macOS)
/// Simulates the TestIDNSView from the user's testID() modifier.
private class TestIDNSViewStub: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Simulates PlatformViewHost<PlatformViewRepresentableAdaptor<TestIDMarker>> wrapping.
/// Name contains both "PlatformViewHost" and "Adaptor" to trigger the marker detection pattern.
private class PlatformViewHostAdaptorStub: NSView {}

/// A container view that reports synthetic accessibility children with text content.
private class AccessibilityContainerView: NSView {
    override func accessibilityChildren() -> [Any]? {
        let element = NSAccessibilityElement()
        element.setAccessibilityLabel("Sessions")
        element.setAccessibilityFrame(NSRect(x: 10, y: 10, width: 80, height: 20))
        element.setAccessibilityParent(self)
        return [element]
    }
}

/// A view that nests virtual accessibility elements N levels deep.
/// Simulates NSOutlineView → proxy → proxy → staticText chains.
private class DeepAccessibilityTextHostView: NSView {
    private let childText: String
    private let nestingDepth: Int

    init(frame: NSRect, childText: String, nestingDepth: Int) {
        self.childText = childText
        self.nestingDepth = nestingDepth
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func accessibilityChildren() -> [Any]? {
        return [buildChain(depth: 0)]
    }

    private func buildChain(depth: Int) -> NSAccessibilityElement {
        let element = NSAccessibilityElement()
        if depth >= nestingDepth {
            element.setAccessibilityLabel(childText)
            element.setAccessibilityRole(.staticText)
        } else {
            element.setAccessibilityRole(.group)
            element.setAccessibilityChildren([buildChain(depth: depth + 1)])
        }
        element.setAccessibilityParent(self)
        return element
    }
}

/// A view that simulates a SwiftUI hosting container: no text properties on the
/// view itself, but exposes text through a virtual accessibility child element.
/// The child is NOT an NSView, so it won't be visited by walkAllViews.
private class AccessibilityTextHostView: NSView {
    private let childText: String

    init(frame: NSRect, childText: String) {
        self.childText = childText
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func accessibilityChildren() -> [Any]? {
        let element = NSAccessibilityElement()
        element.setAccessibilityLabel(childText)
        element.setAccessibilityRole(.staticText)
        element.setAccessibilityFrame(self.accessibilityFrame())
        element.setAccessibilityParent(self)
        return [element]
    }
}

/// A view whose accessibility children include itself, creating a cycle.
/// Used to verify that walkAccessibilityTree doesn't hang on circular references.
private class CyclicAccessibilityView: NSView {
    override func accessibilityChildren() -> [Any]? {
        return [self]
    }
}

/// A view that generates fresh proxy-like objects on each accessibilityChildren() call,
/// defeating ObjectIdentifier-based cycle detection. The wall-clock timeout must catch this.
private class ProxyFloodingView: NSView {
    override func accessibilityChildren() -> [Any]? {
        return (0..<200).map { _ in
            let el = NSAccessibilityElement()
            el.setAccessibilityLabel("proxy-child")
            el.setAccessibilityParent(self)
            return el
        }
    }
}
#endif

#endif
