import XCTest
import Foundation
#if os(macOS)
import AppKit
#endif
@testable import AppXray

#if DEBUG

@MainActor
final class ComponentInspectorTests: XCTestCase {

    let inspector = ComponentInspector()

    #if os(macOS)
    func testTreeFlattensMarkerViews() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let realButton = NSButton(title: "Action", target: nil, action: nil)
        realButton.frame = NSRect(x: 10, y: 10, width: 80, height: 30)
        let marker = MarkerViewStub()
        marker.frame = NSRect(x: 100, y: 10, width: 80, height: 30)
        let markerChild = NSButton(title: "Inner", target: nil, action: nil)
        markerChild.frame = NSRect(x: 0, y: 0, width: 80, height: 30)
        marker.addSubview(markerChild)
        parent.addSubview(realButton)
        parent.addSubview(marker)
        window.contentView?.addSubview(parent)
        window.makeKeyAndOrderFront(nil)

        let tree = inspector.getTree(params: ["depth": 10])
        let treeStr = String(describing: tree)

        XCTAssertFalse(
            treeStr.contains("TestID"),
            "Tree should not contain TestIDMarker wrapper; got: \(treeStr.prefix(500))"
        )
        XCTAssertTrue(
            treeStr.contains("NSButton"),
            "Tree should contain the real button type"
        )

        window.orderOut(nil)
        window.close()
    }

    func testTreeFlattensNestedMarkerViews() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let outerMarker = PlatformViewHostStub()
        outerMarker.frame = NSRect(x: 10, y: 10, width: 100, height: 30)
        let innerMarker = MarkerViewStub()
        innerMarker.frame = NSRect(x: 0, y: 0, width: 100, height: 30)
        let realView = NSTextField(string: "Content")
        realView.frame = NSRect(x: 0, y: 0, width: 100, height: 30)
        innerMarker.addSubview(realView)
        outerMarker.addSubview(innerMarker)
        parent.addSubview(outerMarker)
        window.contentView?.addSubview(parent)
        window.makeKeyAndOrderFront(nil)

        let tree = inspector.getTree(params: ["depth": 10])
        let treeStr = String(describing: tree)

        XCTAssertFalse(
            treeStr.contains("TestID") || treeStr.contains("PlatformViewHostAdaptor"),
            "Tree should flatten both layers of markers; got: \(treeStr.prefix(500))"
        )

        window.orderOut(nil)
        window.close()
    }
    #endif
}

// MARK: - Test helpers

#if os(macOS)
private class MarkerViewStub: NSView {
    // Name contains "TestID" which matches the marker pattern
    override var className: String { "TestIDNSViewStub" }
}

private class PlatformViewHostStub: NSView {
    // Name contains "PlatformViewHost" and "Adaptor" to trigger marker detection
    override var className: String { "PlatformViewHostAdaptorStub" }
}
#endif

#endif
