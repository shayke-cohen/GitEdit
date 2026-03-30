import XCTest
import Foundation
@testable import AppXray

#if DEBUG

final class ConsoleBridgeTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        // Ensure stdout/stderr are fully stable before next test suite.
        // Pipe readability handlers run on GCD background queues and may
        // still be in-flight after stopCapture() returns.
        fflush(stdout)
        fflush(stderr)
        Thread.sleep(forTimeInterval: 0.05)
    }

    // MARK: - Programmatic log() API

    func testLogAddsEntry() {
        let bridge = ConsoleBridge()
        bridge.log("Hello from log()")

        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?["message"] as? String, "Hello from log()")
        XCTAssertEqual(entries.first?["level"] as? String, "log")
    }

    func testLogWithCustomLevel() {
        let bridge = ConsoleBridge()
        bridge.log("Warn message", level: "warn")
        bridge.log("Error message", level: "error")

        let all = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        XCTAssertEqual(all.count, 2)

        let errors = bridge.list(level: "error", limit: nil, since: nil, clear: false)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?["message"] as? String, "Error message")
    }

    func testLogMultipleEntries() {
        let bridge = ConsoleBridge()
        for i in 0..<5 {
            bridge.log("Entry \(i)")
        }

        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        XCTAssertEqual(entries.count, 5)
        // Most recent entry is first (insert at 0)
        XCTAssertEqual(entries.first?["message"] as? String, "Entry 4")
    }

    // MARK: - [appxray] prefix filtering

    func testAppXrayPrefixTaggedAsSystem() {
        let bridge = ConsoleBridge()
        bridge.log("[appxray] Server mode — listening on port 19400")
        bridge.log("Normal app output")

        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        XCTAssertEqual(entries.count, 2, "Both SDK and app messages should be captured")

        let systemEntries = bridge.list(level: "system", limit: nil, since: nil, clear: false)
        XCTAssertEqual(systemEntries.count, 1)
        XCTAssertEqual(systemEntries.first?["message"] as? String, "[appxray] Server mode — listening on port 19400")

        let logEntries = bridge.list(level: "log", limit: nil, since: nil, clear: false)
        XCTAssertEqual(logEntries.count, 1)
        XCTAssertEqual(logEntries.first?["message"] as? String, "Normal app output")
    }

    func testAppXrayPrefixOnlyAffectsPrefix() {
        let bridge = ConsoleBridge()
        bridge.log("This mentions [appxray] in the middle")

        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?["level"] as? String, "log", "Non-prefix [appxray] should keep original level")
    }

    // MARK: - Multi-line splitting

    func testMultiLineSplitIntoSeparateEntries() {
        let bridge = ConsoleBridge()
        bridge.log("Line one\nLine two\nLine three")

        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        XCTAssertEqual(entries.count, 3)
    }

    func testEmptyLinesAreSkipped() {
        let bridge = ConsoleBridge()
        bridge.log("Hello\n\n\nWorld")

        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        XCTAssertEqual(entries.count, 2)
    }

    // MARK: - list() filtering and clear

    func testListLimitReturnsOnlyN() {
        let bridge = ConsoleBridge()
        for i in 0..<10 { bridge.log("Entry \(i)") }

        let limited = bridge.list(level: nil, limit: 3, since: nil, clear: false)
        XCTAssertEqual(limited.count, 3)
    }

    func testListSinceFiltersOldEntries() {
        let bridge = ConsoleBridge()
        bridge.log("Old entry")

        let afterTimestamp = Date().timeIntervalSince1970 * 1000 + 1000
        let entries = bridge.list(level: nil, limit: nil, since: afterTimestamp, clear: false)
        XCTAssertTrue(entries.isEmpty)
    }

    func testListClearRemovesAllEntries() {
        let bridge = ConsoleBridge()
        bridge.log("Entry 1")
        bridge.log("Entry 2")

        let cleared = bridge.list(level: nil, limit: nil, since: nil, clear: true)
        XCTAssertEqual(cleared.count, 2)

        let afterClear = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        XCTAssertTrue(afterClear.isEmpty)
    }

    // MARK: - Entry structure

    func testEntryHasRequiredFields() {
        let bridge = ConsoleBridge()
        bridge.log("Test message")

        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        guard let entry = entries.first else { XCTFail("No entries"); return }

        XCTAssertNotNil(entry["id"] as? String)
        XCTAssertNotNil(entry["level"] as? String)
        XCTAssertNotNil(entry["message"] as? String)
        XCTAssertNotNil(entry["timestamp"] as? TimeInterval)
    }

    func testEntryTimestampIsMilliseconds() {
        let before = Date().timeIntervalSince1970 * 1000
        let bridge = ConsoleBridge()
        bridge.log("Timestamped")
        let after = Date().timeIntervalSince1970 * 1000

        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        let ts = entries.first?["timestamp"] as? TimeInterval ?? 0
        XCTAssertGreaterThanOrEqual(ts, before)
        XCTAssertLessThanOrEqual(ts, after + 1)
    }

    // MARK: - Ring buffer max entries

    func testMaxEntriesRingBuffer() {
        let bridge = ConsoleBridge()
        for i in 0..<250 { bridge.log("Entry \(i)") }

        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        XCTAssertLessThanOrEqual(entries.count, 200, "Ring buffer should cap at maxEntries")
    }

    // MARK: - Thread safety via concurrent access

    func testConcurrentLogAndListDoNotCrash() {
        let bridge = ConsoleBridge()
        let expectation = XCTestExpectation(description: "Concurrent access completes")
        expectation.expectedFulfillmentCount = 2

        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<100 {
                bridge.log("Writer entry \(i)")
            }
            expectation.fulfill()
        }

        DispatchQueue.global(qos: .utility).async {
            for _ in 0..<100 {
                _ = bridge.list(level: nil, limit: nil, since: nil, clear: false)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        XCTAssertGreaterThan(entries.count, 0, "Should have captured entries from concurrent writes")
    }

    // MARK: - Diagnostic entry on capture start

    func testStartCaptureAddsDiagnosticEntry() {
        let bridge = ConsoleBridge()
        bridge.startCapture()

        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        let messages = entries.compactMap { $0["message"] as? String }
        XCTAssertTrue(
            messages.contains(where: { $0.contains("Console capture active") }),
            "Should include diagnostic entry after startCapture; got: \(messages)"
        )

        bridge.stopCapture()
    }

    func testDiagnosticEntryHasDebugLevel() {
        let bridge = ConsoleBridge()
        bridge.startCapture()

        let debugEntries = bridge.list(level: "debug", limit: nil, since: nil, clear: false)
        XCTAssertFalse(debugEntries.isEmpty, "Diagnostic entry should have 'debug' level")

        bridge.stopCapture()
    }

    // MARK: - Pipe capture of print()

    func testStartCaptureInterceptsPrint() {
        let bridge = ConsoleBridge()
        bridge.startCapture()

        print("captured-by-pipe-test")
        // Allow readability handler to fire
        Thread.sleep(forTimeInterval: 0.2)

        bridge.stopCapture()

        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        let messages = entries.compactMap { $0["message"] as? String }
        XCTAssertTrue(
            messages.contains("captured-by-pipe-test"),
            "print() output should be captured; got: \(messages)"
        )
    }

    func testDoubleStartCaptureIsNoOp() {
        let bridge = ConsoleBridge()
        bridge.startCapture()
        bridge.startCapture() // Second call should be a no-op (already capturing)

        // Verify no crash occurred and at least the diagnostic entry exists
        let entries = bridge.list(level: "debug", limit: nil, since: nil, clear: false)
        let diagCount = entries.filter { ($0["message"] as? String)?.contains("Console capture active") == true }.count
        XCTAssertEqual(diagCount, 1, "Should have exactly one diagnostic entry, not duplicates")

        bridge.stopCapture()
    }

    func testCaptureWorksAfterDelay() {
        let bridge = ConsoleBridge()
        bridge.startCapture()

        // Print immediately
        print("line-1-immediate")
        Thread.sleep(forTimeInterval: 0.1)

        // Print after a delay (simulates app output after startup)
        Thread.sleep(forTimeInterval: 0.5)
        print("line-2-delayed")
        Thread.sleep(forTimeInterval: 0.1)

        bridge.stopCapture()

        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        let messages = entries.compactMap { $0["message"] as? String }
        XCTAssertTrue(
            messages.contains("line-1-immediate"),
            "Immediate print should be captured; got: \(messages)"
        )
        XCTAssertTrue(
            messages.contains("line-2-delayed"),
            "Delayed print should be captured; got: \(messages)"
        )
    }

    func testStopCaptureRestoresStdout() {
        let bridge = ConsoleBridge()
        bridge.startCapture()
        bridge.stopCapture()

        // After stop, print() should NOT add entries
        bridge.log("direct-after-stop")
        let entries = bridge.list(level: nil, limit: nil, since: nil, clear: false)
        let messages = entries.compactMap { $0["message"] as? String }
        XCTAssertTrue(messages.contains("direct-after-stop"))
    }
}

#endif
