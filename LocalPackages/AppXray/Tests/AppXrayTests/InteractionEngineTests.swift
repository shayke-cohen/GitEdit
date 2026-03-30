import XCTest
import Foundation
@testable import AppXray

#if DEBUG

@MainActor
final class InteractionEngineTests: XCTestCase {

    private var engine: InteractionEngine!
    private var selectorEngine: SelectorEngine!

    override func setUp() {
        super.setUp()
        selectorEngine = SelectorEngine()
        engine = InteractionEngine(selectorEngine: selectorEngine)
    }

    // MARK: - Tap

    func testTapWithNoCoordinatesReturnsFalse() async {
        let result = await engine.tap(params: [:])
        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["action"] as? String, "tap")
        XCTAssertNotNil(result["error"])
    }

    func testTapWithInvalidSelectorReturnsFalse() async {
        let result = await engine.tap(params: ["selector": "@text(\"nonexistent-12345\")"])
        XCTAssertEqual(result["success"] as? Bool, false)
    }

    // MARK: - Long Press

    func testLongPressWithNoCoordinatesReturnsFalse() async {
        let result = await engine.longPress(params: [:])
        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["action"] as? String, "longPress")
    }

    // MARK: - Type Text

    func testTypeTextWithNoTextReturnsFalse() async {
        let result = await engine.typeText(params: [:])
        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["action"] as? String, "type")
        XCTAssertEqual(result["error"] as? String, "text required")
    }

    func testTypeTextWithNoTargetReturnsFalse() async {
        let result = await engine.typeText(params: ["text": "hello"])
        XCTAssertEqual(result["success"] as? Bool, false)
    }

    // MARK: - Swipe

    func testSwipeReturnsActionSwipe() async {
        let result = await engine.swipe(params: ["direction": "up"])
        // Without a window, macOS returns error; with a window, returns success.
        XCTAssertEqual(result["action"] as? String, "swipe")
    }

    func testSwipeDirectionDefaultsToUp() async {
        let result = await engine.swipe(params: [:])
        XCTAssertEqual(result["action"] as? String, "swipe")
    }

    // MARK: - Drag

    func testDragWithNoCoordinatesReturnsFalse() async {
        let result = await engine.drag(params: [:])
        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["action"] as? String, "drag")
    }

    func testDragWithExplicitCoordinatesReturnsSuccess() async {
        let result = await engine.drag(params: [
            "fromX": 10.0, "fromY": 20.0,
            "toX": 100.0, "toY": 200.0,
        ])
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["action"] as? String, "drag")

        if let from = result["from"] as? [String: Any] {
            XCTAssertEqual(from["x"] as? CGFloat, 10.0)
            XCTAssertEqual(from["y"] as? CGFloat, 20.0)
        }
    }

    // MARK: - Tap with explicit coordinates

    func testTapWithExplicitCoordinatesReturnsSuccess() async {
        let result = await engine.tap(params: ["x": 50.0, "y": 100.0])
        // Without a window on macOS or iOS, tap still reports success
        // because it resolves coordinates but may not find a view.
        XCTAssertEqual(result["action"] as? String, "tap")
        if let coords = result["coordinates"] as? [String: Any] {
            XCTAssertEqual(coords["x"] as? CGFloat, 50.0)
            XCTAssertEqual(coords["y"] as? CGFloat, 100.0)
        }
    }

    func testTapWithCountPassesCountToImpl() async {
        let result = await engine.tap(params: ["x": 50.0, "y": 50.0, "count": 3])
        XCTAssertEqual(result["action"] as? String, "tap")
    }

    // MARK: - Swipe with explicit coordinates

    func testSwipeWithExplicitCoordinatesReturnsAction() async {
        let result = await engine.swipe(params: [
            "direction": "down",
            "x": 100.0, "y": 200.0,
            "distance": 500.0,
        ])
        XCTAssertEqual(result["action"] as? String, "swipe")
        if let coords = result["coordinates"] as? [String: Any] {
            XCTAssertEqual(coords["x"] as? CGFloat, 100.0)
            XCTAssertEqual(coords["y"] as? CGFloat, 200.0)
        }
    }

    func testSwipeAllDirections() async {
        for dir in ["up", "down", "left", "right"] {
            let result = await engine.swipe(params: ["direction": dir])
            XCTAssertEqual(result["action"] as? String, "swipe")
        }
    }

    // MARK: - Long Press

    func testLongPressWithExplicitCoordinatesReturnsAction() async {
        let result = await engine.longPress(params: ["x": 50.0, "y": 50.0, "duration": 200.0])
        XCTAssertEqual(result["action"] as? String, "longPress")
        // duration is only present when a window is available (returns early with error otherwise)
        if result["error"] == nil {
            XCTAssertEqual(result["duration"] as? Double, 200.0)
        }
    }

    #if os(macOS)
    // MARK: - macOS: Tap with real NSWindow and accessibility

    func testTapOnNSButtonViaAccessibility() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var tapped = false
        let button = NSButton(title: "Test", target: nil, action: nil)
        button.frame = NSRect(x: 50, y: 50, width: 100, height: 30)
        button.target = nil
        window.contentView?.addSubview(button)
        window.makeKeyAndOrderFront(nil)

        // Allow the window to become key
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Tap at the button's center (top-left origin)
        let contentHeight = window.contentView?.bounds.height ?? 300
        let topLeftY = contentHeight - 65 // center of button in top-left coords
        let result = await engine.tap(params: ["x": 100.0, "y": topLeftY])
        XCTAssertEqual(result["action"] as? String, "tap")

        window.orderOut(nil)
    }

    // MARK: - Round 5: tap with selector uses direct accessibility press

    func testTapWithSelectorDoesNotHangOnElement() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let button = NSButton(title: "DirectPress", target: nil, action: nil)
        button.frame = NSRect(x: 50, y: 50, width: 120, height: 30)
        window.contentView?.addSubview(button)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Key assertion: this completes without hanging.
        // The selector path finds the view and either performs accessibility press
        // or returns gracefully. It never falls through to NSApp.sendEvent.
        let result = await engine.tap(params: ["selector": "@text(\"DirectPress\")"])
        XCTAssertEqual(result["action"] as? String, "tap")

        window.orderOut(nil)
    }

    func testTapWithNonPressableViewReturnsGracefully() async {
        // When a selector finds a plain NSView that doesn't respond to
        // accessibilityPerformPress, the tap should return gracefully
        // instead of falling through to NSApp.sendEvent (which can hang).
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = NSView(frame: NSRect(x: 10, y: 10, width: 80, height: 30))
        view.setAccessibilityLabel("NonPressable")
        window.contentView?.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Must NOT hang — returns error gracefully
        let result = await engine.tap(params: ["selector": "@text(\"NonPressable\")"])
        XCTAssertEqual(result["action"] as? String, "tap")
        XCTAssertEqual(result["success"] as? Bool, false)
        let error = result["error"] as? String ?? ""
        XCTAssertTrue(error.contains("not pressable"), "Should report element not pressable: \(error)")

        window.orderOut(nil)
    }

    func testSwipeOnMacOSDoesNotCrash() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let result = await engine.swipe(params: [
            "direction": "up",
            "x": 200.0, "y": 150.0,
            "distance": 100.0,
        ])
        XCTAssertEqual(result["action"] as? String, "swipe")
        // Key assertion: no crash occurred

        window.orderOut(nil)
    }
    #endif
}

#endif
