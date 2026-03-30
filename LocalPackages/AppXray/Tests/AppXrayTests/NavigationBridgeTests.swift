import XCTest
import Foundation
@testable import AppXray

#if DEBUG

@MainActor
final class NavigationBridgeTests: XCTestCase {

    // MARK: - Default state (no bindings)

    func testGetStateWithNoBindingsReturnsUnknown() {
        let bridge = NavigationBridge()
        let state = bridge.getState()
        let route = state["currentRoute"] as? [String: Any]
        XCTAssertNotNil(route)
    }

    // MARK: - Selection Binding

    func testBindSelectionGetState() {
        let bridge = NavigationBridge()
        var current = "dashboard"
        let available = ["dashboard", "settings", "profile"]

        bridge.bindSelection(NavigationBridge.SelectionBinding(
            getCurrent: { current },
            setSelection: { current = $0 },
            getAvailable: { available }
        ))

        let state = bridge.getState()
        let route = state["currentRoute"] as? [String: Any]
        XCTAssertEqual(route?["name"] as? String, "dashboard")
        XCTAssertEqual(state["type"] as? String, "selection")

        let routes = state["availableRoutes"] as? [String]
        XCTAssertEqual(routes, available)

        XCTAssertEqual(state["canGoBack"] as? Bool, false)
        XCTAssertEqual(state["canGoForward"] as? Bool, false)
    }

    func testBindSelectionExecuteSelect() async {
        let bridge = NavigationBridge()
        var current = "dashboard"

        bridge.bindSelection(NavigationBridge.SelectionBinding(
            getCurrent: { current },
            setSelection: { current = $0 },
            getAvailable: { ["dashboard", "settings", "profile"] }
        ))

        let result = await bridge.execute(params: ["action": "select", "route": "settings"])
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(current, "settings")
    }

    func testBindSelectionExecutePushActsAsSelect() async {
        let bridge = NavigationBridge()
        var current = "dashboard"

        bridge.bindSelection(NavigationBridge.SelectionBinding(
            getCurrent: { current },
            setSelection: { current = $0 },
            getAvailable: { ["dashboard", "settings"] }
        ))

        let result = await bridge.execute(params: ["action": "push", "route": "settings"])
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(current, "settings")
    }

    func testBindSelectionExecuteSelectRequiresRoute() async {
        let bridge = NavigationBridge()

        bridge.bindSelection(NavigationBridge.SelectionBinding(
            getCurrent: { "dashboard" },
            setSelection: { _ in },
            getAvailable: { ["dashboard"] }
        ))

        let result = await bridge.execute(params: ["action": "select"])
        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertNotNil(result["error"])
    }

    // MARK: - Path Binding

    func testBindSwiftUIPathGetState() {
        let bridge = NavigationBridge()
        var stack = ["home", "detail"]

        bridge.bindSwiftUIPath(NavigationBridge.NavigationPathBinding(
            getStack: { stack },
            push: { stack.append($0) },
            pop: { if !stack.isEmpty { stack.removeLast() } },
            replace: { stack = [$0] }
        ))

        let state = bridge.getState()
        let route = state["currentRoute"] as? [String: Any]
        XCTAssertEqual(route?["name"] as? String, "detail")
        XCTAssertEqual(state["type"] as? String, "stack")
        XCTAssertEqual(state["canGoBack"] as? Bool, true)
    }

    func testBindSwiftUIPathPush() async {
        let bridge = NavigationBridge()
        var stack = ["home"]

        bridge.bindSwiftUIPath(NavigationBridge.NavigationPathBinding(
            getStack: { stack },
            push: { stack.append($0) },
            pop: { if !stack.isEmpty { stack.removeLast() } },
            replace: { stack = [$0] }
        ))

        let result = await bridge.execute(params: ["action": "push", "route": "detail"])
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(stack, ["home", "detail"])
    }

    func testBindSwiftUIPathPop() async {
        let bridge = NavigationBridge()
        var stack = ["home", "detail"]

        bridge.bindSwiftUIPath(NavigationBridge.NavigationPathBinding(
            getStack: { stack },
            push: { stack.append($0) },
            pop: { if !stack.isEmpty { stack.removeLast() } },
            replace: { stack = [$0] }
        ))

        let result = await bridge.execute(params: ["action": "pop"])
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(stack, ["home"])
    }

    func testBindSwiftUIPathReplace() async {
        let bridge = NavigationBridge()
        var stack = ["home", "detail"]

        bridge.bindSwiftUIPath(NavigationBridge.NavigationPathBinding(
            getStack: { stack },
            push: { stack.append($0) },
            pop: { if !stack.isEmpty { stack.removeLast() } },
            replace: { stack = [$0] }
        ))

        let result = await bridge.execute(params: ["action": "replace", "route": "settings"])
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(stack, ["settings"])
    }

    // MARK: - No binding error

    func testExecuteWithNoBindingReturnsError() async {
        let bridge = NavigationBridge()
        let result = await bridge.execute(params: ["action": "push", "route": "foo"])
        XCTAssertEqual(result["success"] as? Bool, false)
        let error = result["error"] as? String ?? ""
        XCTAssertTrue(error.contains("bindSwiftUIPath") || error.contains("bindSelection"))
    }

    // MARK: - Navigate completes without timeout (Issue 2)

    func testSelectionNavigateCompletesQuickly() async {
        let bridge = NavigationBridge()
        var current = "dashboard"

        bridge.bindSelection(NavigationBridge.SelectionBinding(
            getCurrent: { current },
            setSelection: { current = $0 },
            getAvailable: { ["dashboard", "settings", "liveMissions"] }
        ))

        let start = Date()
        let result = await bridge.execute(params: ["action": "select", "route": "liveMissions"])
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(current, "liveMissions")
        XCTAssertLessThan(elapsed, 5.0, "Navigate should complete well within timeout")
    }

    func testPathPushCompletesQuickly() async {
        let bridge = NavigationBridge()
        var stack = ["home"]

        bridge.bindSwiftUIPath(NavigationBridge.NavigationPathBinding(
            getStack: { stack },
            push: { stack.append($0) },
            pop: { if !stack.isEmpty { stack.removeLast() } },
            replace: { stack = [$0] }
        ))

        let start = Date()
        let result = await bridge.execute(params: ["action": "push", "route": "detail"])
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(stack, ["home", "detail"])
        XCTAssertLessThan(elapsed, 5.0, "Push should complete well within timeout")
    }

    func testPathPopCompletesQuickly() async {
        let bridge = NavigationBridge()
        var stack = ["home", "detail"]

        bridge.bindSwiftUIPath(NavigationBridge.NavigationPathBinding(
            getStack: { stack },
            push: { stack.append($0) },
            pop: { if !stack.isEmpty { stack.removeLast() } },
            replace: { stack = [$0] }
        ))

        let start = Date()
        let result = await bridge.execute(params: ["action": "goBack"])
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(stack, ["home"])
        XCTAssertLessThan(elapsed, 5.0, "Pop should complete well within timeout")
    }

    func testPathReplaceCompletesQuickly() async {
        let bridge = NavigationBridge()
        var stack = ["home", "detail"]

        bridge.bindSwiftUIPath(NavigationBridge.NavigationPathBinding(
            getStack: { stack },
            push: { stack.append($0) },
            pop: { if !stack.isEmpty { stack.removeLast() } },
            replace: { stack = [$0] }
        ))

        let start = Date()
        let result = await bridge.execute(params: ["action": "replace", "route": "settings"])
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(stack, ["settings"])
        XCTAssertLessThan(elapsed, 5.0, "Replace should complete well within timeout")
    }

    func testMultipleNavigationsInSequence() async {
        let bridge = NavigationBridge()
        var current = "dashboard"
        let routes = ["settings", "liveMissions", "board", "inbox", "sessions", "chains"]

        bridge.bindSelection(NavigationBridge.SelectionBinding(
            getCurrent: { current },
            setSelection: { current = $0 },
            getAvailable: { routes + ["dashboard"] }
        ))

        for route in routes {
            let result = await bridge.execute(params: ["action": "select", "route": route])
            XCTAssertEqual(result["success"] as? Bool, true, "Navigate to \(route) should succeed")
            XCTAssertEqual(current, route)
        }
    }

    // MARK: - Path binding takes priority over selection

    func testPathBindingTakesPriorityOverSelection() {
        let bridge = NavigationBridge()
        var stack = ["home"]

        bridge.bindSwiftUIPath(NavigationBridge.NavigationPathBinding(
            getStack: { stack },
            push: { stack.append($0) },
            pop: { if !stack.isEmpty { stack.removeLast() } },
            replace: { stack = [$0] }
        ))
        bridge.bindSelection(NavigationBridge.SelectionBinding(
            getCurrent: { "tab1" },
            setSelection: { _ in },
            getAvailable: { ["tab1", "tab2"] }
        ))

        let state = bridge.getState()
        XCTAssertEqual(state["type"] as? String, "stack")
    }
}

#endif
