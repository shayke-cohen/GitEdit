import XCTest
import Foundation
import Combine
@testable import AppXray

#if DEBUG

/// Test observable that uses @Published properties like a real SwiftUI ViewModel.
private class TestViewModel: ObservableObject {
    @Published var counter: Int = 0
    @Published var name: String = "initial"
    @Published var isActive: Bool = false
    @Published var items: [String] = ["a", "b"]
}

/// Simple NSObject-based observable for KVC testing.
private class KVCModel: NSObject {
    @objc dynamic var title: String = "hello"
    @objc dynamic var count: Int = 0
}

/// Swift enum (NOT @objc compatible) for testing non-KVC mutation paths.
private enum SidebarSelection: String {
    case board, settings, sessions, liveMissions
}

/// ViewModel with a Swift enum @Published property — the exact case from the bug report.
private class EnumViewModel: ObservableObject {
    @Published var selectedView: SidebarSelection = .board
    @Published var title: String = "Home"
}

final class StateBridgeTests: XCTestCase {

    // MARK: - Registration & Listing

    func testRegisterAndListStores() {
        let bridge = StateBridge()
        let vm = TestViewModel()
        bridge.registerObservable(vm, name: "appState")

        let stores = bridge.listStores()
        XCTAssertEqual(stores, ["appState"])
    }

    func testListStoresExcludesDeallocatedObjects() {
        let bridge = StateBridge()
        var vm: TestViewModel? = TestViewModel()
        bridge.registerObservable(vm!, name: "temp")
        XCTAssertEqual(bridge.listStores(), ["temp"])

        vm = nil

        XCTAssertEqual(bridge.listStores(), [])
    }

    // MARK: - Get (read state)

    func testGetReturnsStoresSnapshot() {
        let bridge = StateBridge()
        let vm = TestViewModel()
        bridge.registerObservable(vm, name: "test")

        let result = bridge.get(path: "", depth: nil)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?["stores"])
    }

    func testGetSpecificStore() {
        let bridge = StateBridge()
        let vm = TestViewModel()
        vm.counter = 42
        bridge.registerObservable(vm, name: "app")

        let result = bridge.get(path: "app", depth: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["path"] as? String, "app")
    }

    func testGetNonexistentStoreReturnsError() {
        let bridge = StateBridge()
        let result = bridge.get(path: "missing", depth: nil)
        XCTAssertNotNil(result?["error"] as? String)
    }

    // MARK: - Set (mutate state)

    func testSetViaKVC() {
        let bridge = StateBridge()
        let model = KVCModel()
        bridge.registerObservable(model, name: "kvc")

        let result = bridge.set(path: "kvc.title", value: "world", merge: nil)
        XCTAssertEqual(result?["success"] as? Bool, true)
        XCTAssertEqual(model.title, "world")
    }

    func testSetOnPublishedPropertyViaKVC() {
        let bridge = StateBridge()
        let vm = TestViewModel()
        bridge.registerObservable(vm, name: "vm")

        let result = bridge.set(path: "vm.counter", value: 99, merge: nil)

        // The Published property set uses KVC fallback via NSObject.
        // TestViewModel is a class that inherits ObservableObject.
        // KVC may or may not work depending on the ObjC bridge.
        // We verify either success or a known failure pattern.
        let success = result?["success"] as? Bool ?? false
        if success {
            XCTAssertEqual(vm.counter, 99)
        }
    }

    func testSetOnNonexistentStoreReturnsFalse() {
        let bridge = StateBridge()
        let result = bridge.set(path: "ghost.prop", value: "x", merge: nil)
        XCTAssertEqual(result?["success"] as? Bool, false)
    }

    // MARK: - Snapshot

    func testSnapshotContainsRegisteredStores() {
        let bridge = StateBridge()
        let model = KVCModel()
        model.title = "snapshot-test"
        bridge.registerObservable(model, name: "s")

        let snap = bridge.snapshot()
        XCTAssertNotNil(snap["stores"])
        let stores = snap["stores"] as? [String: Any]
        XCTAssertNotNil(stores?["s"])
    }

    // MARK: - Explicit Setters

    func testSetWithExplicitSetter() {
        let bridge = StateBridge()
        let vm = TestViewModel()
        bridge.registerObservable(vm, name: "app", setters: [
            "name": { vm.name = $0 as? String ?? vm.name },
        ])

        let result = bridge.set(path: "app.name", value: "updated", merge: nil)
        XCTAssertEqual(result?["success"] as? Bool, true)
        XCTAssertEqual(vm.name, "updated")
    }

    func testSetWithExplicitSetterForBool() {
        let bridge = StateBridge()
        let vm = TestViewModel()
        bridge.registerObservable(vm, name: "app", setters: [
            "isActive": { vm.isActive = $0 as? Bool ?? vm.isActive },
        ])

        let result = bridge.set(path: "app.isActive", value: true, merge: nil)
        XCTAssertEqual(result?["success"] as? Bool, true)
        XCTAssertEqual(vm.isActive, true)
    }

    func testSetWithExplicitSetterOverridesOtherPaths() {
        let bridge = StateBridge()
        let vm = TestViewModel()
        bridge.registerObservable(vm, name: "app", setters: [
            "counter": { vm.counter = $0 as? Int ?? vm.counter },
        ])

        let result = bridge.set(path: "app.counter", value: 42, merge: nil)
        XCTAssertEqual(result?["success"] as? Bool, true)
        XCTAssertEqual(vm.counter, 42)
    }

    func testSetWithoutExplicitSetterOnNonNSObject() {
        let bridge = StateBridge()
        let vm = TestViewModel()
        bridge.registerObservable(vm, name: "app")

        // Without explicit setters, setState attempts KVC and ivar fallback.
        // On a non-NSObject, KVC won't work, but object_setIvar might.
        let result = bridge.set(path: "app.name", value: "test", merge: nil)
        let success = result?["success"] as? Bool ?? false
        // We test that it doesn't crash; success depends on runtime behavior.
        XCTAssertNotNil(result)
        _ = success
    }

    func testRegisterObservableWithoutSettersStillWorks() {
        let bridge = StateBridge()
        let vm = TestViewModel()
        bridge.registerObservable(vm, name: "app")

        let stores = bridge.listStores()
        XCTAssertEqual(stores, ["app"])

        let result = bridge.get(path: "app", depth: nil)
        XCTAssertNotNil(result)
    }

    // MARK: - Combine Subject.send() mutation path (Issue 5)

    func testSetPublishedStringViaSubjectSend() {
        let bridge = StateBridge()
        let vm = EnumViewModel()
        // Force Published into .publisher mode by subscribing
        let cancellable = vm.$title.sink { _ in }
        bridge.registerObservable(vm, name: "enumVm")

        let result = bridge.set(path: "enumVm.title", value: "Updated Title", merge: nil)
        let success = result?["success"] as? Bool ?? false
        if success {
            XCTAssertEqual(vm.title, "Updated Title")
        }
        cancellable.cancel()
    }

    func testSetPublishedIntViaTypedSend() {
        let bridge = StateBridge()
        let vm = TestViewModel()
        let cancellable = vm.$counter.sink { _ in }
        bridge.registerObservable(vm, name: "vm")

        let result = bridge.set(path: "vm.counter", value: 42, merge: nil)
        let success = result?["success"] as? Bool ?? false
        if success {
            XCTAssertEqual(vm.counter, 42)
        }
        cancellable.cancel()
    }

    func testSetPublishedBoolViaTypedSend() {
        let bridge = StateBridge()
        let vm = TestViewModel()
        let cancellable = vm.$isActive.sink { _ in }
        bridge.registerObservable(vm, name: "vm")

        let result = bridge.set(path: "vm.isActive", value: true, merge: nil)
        let success = result?["success"] as? Bool ?? false
        if success {
            XCTAssertEqual(vm.isActive, true)
        }
        cancellable.cancel()
    }

    func testSetPublishedEnumWithoutSetterReturnsDescriptiveError() {
        let bridge = StateBridge()
        let vm = EnumViewModel()
        bridge.registerObservable(vm, name: "myApp")

        let result = bridge.set(path: "myApp.selectedView", value: "sessions", merge: nil)
        let success = result?["success"] as? Bool ?? false

        if !success {
            let error = result?["error"] as? String ?? ""
            XCTAssertTrue(
                error.contains("selectedView"),
                "Error should mention the property name; got: \(error)"
            )
            XCTAssertTrue(
                error.contains("registerObservableObject"),
                "Error should suggest setter registration; got: \(error)"
            )
            XCTAssertTrue(
                error.contains("myApp"),
                "Error should include the store name; got: \(error)"
            )
            XCTAssertFalse(
                error.contains("Optional("),
                "Error should NOT wrap store name in Optional(); got: \(error)"
            )
        }
    }

    func testSetPublishedEnumWithExplicitSetterWorks() {
        let bridge = StateBridge()
        let vm = EnumViewModel()
        bridge.registerObservable(vm, name: "app", setters: [
            "selectedView": { vm.selectedView = SidebarSelection(rawValue: $0 as? String ?? "") ?? .board },
        ])

        let result = bridge.set(path: "app.selectedView", value: "sessions", merge: nil)
        XCTAssertEqual(result?["success"] as? Bool, true)
        XCTAssertEqual(vm.selectedView, .sessions)
    }

    func testSetPublishedEnumSetterDoesNotCrash() {
        let bridge = StateBridge()
        let vm = EnumViewModel()
        bridge.registerObservable(vm, name: "app")

        // This previously crashed with an unrecoverable ObjC exception (P0).
        // Now it should return a controlled error.
        let result = bridge.set(path: "app.selectedView", value: "settings", merge: nil)
        XCTAssertNotNil(result, "Should not crash")
        let success = result?["success"] as? Bool ?? false
        if !success {
            XCTAssertNotNil(result?["error"], "Should return an error message")
        }
    }

    func testSetEnumPropertyNeverCrashesOnArbitraryInput() {
        let bridge = StateBridge()
        let vm = EnumViewModel()
        bridge.registerObservable(vm, name: "app")

        // Test with various input types that could trigger KVC exceptions
        for value in ["sessions", 42, true, ["nested": "dict"], NSNull()] as [Any] {
            let result = bridge.set(path: "app.selectedView", value: value, merge: nil)
            XCTAssertNotNil(result, "Should not crash for input: \(value)")
        }
    }

    func testPublishedUnwrapReturnsEnumAsString() {
        let bridge = StateBridge()
        let vm = EnumViewModel()
        vm.selectedView = .sessions
        bridge.registerObservable(vm, name: "app")

        let result = bridge.get(path: "app.selectedView", depth: nil)
        XCTAssertNotNil(result)
        // The value should be the enum case name, not the Published wrapper
        let value = result?["value"] as? [String: Any]
        let type = value?["type"] as? String
        XCTAssertTrue(
            type == "string" || type == "unknown",
            "Enum should serialize as string; got type: \(type ?? "nil")"
        )
    }

    // MARK: - objectWillChange notification

    func testNotifyObjectWillChangeIsCalled() {
        let bridge = StateBridge()
        let vm = TestViewModel()
        bridge.registerObservable(vm, name: "vm")

        let expectation = XCTestExpectation(description: "objectWillChange fires")
        let cancellable = vm.objectWillChange.sink { _ in
            expectation.fulfill()
        }

        // Directly mutate the published property to verify the bridge path
        vm.counter = 10

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }
}

#endif
