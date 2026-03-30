import XCTest
import Foundation
import Combine
@testable import AppXray

#if DEBUG

private class MockTransport: AppXrayTransport {
    var handlers: [String: @Sendable ([String: Any]) async throws -> Any] = [:]

    func registerHandler(_ method: String, handler: @escaping @Sendable ([String: Any]) async throws -> Any) {
        handlers[method] = handler
    }

    func sendNotification(_ method: String, params: [String: Any]?) {}

    func call(_ method: String, params: [String: Any] = [:]) async throws -> Any {
        guard let handler = handlers[method] else {
            throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "No handler for \(method)"])
        }
        return try await handler(params)
    }
}

private class TestStore: ObservableObject {
    @Published var counter: Int = 0
    @Published var name: String = "test"
    @Published var active: Bool = true
    @Published var tags: [String] = ["a", "b"]
}

@MainActor
final class ProtocolHandlerTests: XCTestCase {

    private var transport: MockTransport!
    private var stateBridge: StateBridge!
    private var store: TestStore!
    private var protocolHandler: ProtocolHandler!

    @MainActor
    override func setUp() {
        super.setUp()
        transport = MockTransport()
        stateBridge = StateBridge()
        store = TestStore()
        stateBridge.registerObservable(store!, name: "testStore")

        let componentInspector = ComponentInspector()
        let timeline = TimelineBridge()
        let networkInterceptor = NetworkInterceptor(timeline: timeline)
        let storageBridge = StorageBridge()
        let navigationBridge = NavigationBridge()
        let timeTravelEngine = TimeTravelEngine(stateBridge: stateBridge, navigationBridge: navigationBridge)
        let chaosEngine = ChaosEngine(networkInterceptor: networkInterceptor)
        let errorBuffer = ErrorBuffer(timeline: timeline)
        let consoleBridge = ConsoleBridge()
        let selectorEngine = SelectorEngine()
        let interactionEngine = InteractionEngine(selectorEngine: selectorEngine)
        let screenshotEngine = ScreenshotEngine()
        let waitEngine = WaitEngine(selectorEngine: selectorEngine, networkInterceptor: networkInterceptor, stateBridge: stateBridge)
        let recordEngine = RecordEngine(selectorEngine: selectorEngine)

        protocolHandler = ProtocolHandler(
            componentInspector: componentInspector,
            stateBridge: stateBridge,
            networkInterceptor: networkInterceptor,
            storageBridge: storageBridge,
            navigationBridge: navigationBridge,
            timeTravelEngine: timeTravelEngine,
            chaosEngine: chaosEngine,
            errorBuffer: errorBuffer,
            consoleBridge: consoleBridge,
            selectorEngine: selectorEngine,
            interactionEngine: interactionEngine,
            screenshotEngine: screenshotEngine,
            waitEngine: waitEngine,
            recordEngine: recordEngine,
            timeline: timeline
        )
        protocolHandler.registerHandlers(on: transport)
    }

    // MARK: - schema.get

    func testSchemaGetIsRegistered() {
        XCTAssertNotNil(transport.handlers["schema.get"])
    }

    func testSchemaGetReturnsStoresList() async throws {
        let result = try await transport.call("schema.get", params: [:])
        guard let dict = result as? [String: Any] else {
            XCTFail("Expected dictionary result"); return
        }
        let stores = dict["stores"] as? [String]
        XCTAssertNotNil(stores)
        XCTAssertTrue(stores?.contains("testStore") == true)
    }

    func testSchemaGetWithPathReturnsSchema() async throws {
        let result = try await transport.call("schema.get", params: ["path": "testStore"])
        guard let dict = result as? [String: Any] else {
            XCTFail("Expected dictionary result"); return
        }
        XCTAssertEqual(dict["path"] as? String, "testStore")
        XCTAssertNotNil(dict["schema"])
    }

    func testSchemaGetEmptyPathReturnsAllSchemas() async throws {
        let result = try await transport.call("schema.get", params: ["path": ""])
        guard let dict = result as? [String: Any] else {
            XCTFail("Expected dictionary result"); return
        }
        let schema = dict["schema"] as? [String: Any]
        XCTAssertNotNil(schema?["testStore"])
    }

    // MARK: - metrics.get

    func testMetricsGetIsRegistered() {
        XCTAssertNotNil(transport.handlers["metrics.get"])
    }

    func testMetricsGetReturnsMemory() async throws {
        let result = try await transport.call("metrics.get")
        guard let dict = result as? [String: Any] else {
            XCTFail("Expected dictionary result"); return
        }
        let memory = dict["memory"] as? [String: Any]
        XCTAssertNotNil(memory, "Should have memory info")
        XCTAssertNotNil(memory?["resident"], "Should have resident memory")
        XCTAssertNotNil(memory?["virtual"], "Should have virtual memory")
    }

    func testMetricsGetReturnsUptime() async throws {
        let result = try await transport.call("metrics.get")
        guard let dict = result as? [String: Any] else {
            XCTFail("Expected dictionary result"); return
        }
        let uptime = dict["uptime"] as? TimeInterval
        XCTAssertNotNil(uptime)
        XCTAssertGreaterThan(uptime ?? 0, 0)
    }

    func testMetricsGetReturnsProcessorCount() async throws {
        let result = try await transport.call("metrics.get")
        guard let dict = result as? [String: Any] else {
            XCTFail("Expected dictionary result"); return
        }
        let cpuCount = dict["processorCount"] as? Int
        XCTAssertNotNil(cpuCount)
        XCTAssertGreaterThan(cpuCount ?? 0, 0)
    }

    func testMetricsGetReturnsThermalState() async throws {
        let result = try await transport.call("metrics.get")
        guard let dict = result as? [String: Any] else {
            XCTFail("Expected dictionary result"); return
        }
        let thermal = dict["thermalState"] as? String
        XCTAssertNotNil(thermal)
        XCTAssertTrue(["nominal", "fair", "serious", "critical", "unknown"].contains(thermal ?? ""))
    }

    // MARK: - bindings.get

    func testBindingsGetIsRegistered() {
        XCTAssertNotNil(transport.handlers["bindings.get"])
    }

    func testBindingsGetReturnsBindings() async throws {
        let result = try await transport.call("bindings.get")
        guard let dict = result as? [String: Any] else {
            XCTFail("Expected dictionary result"); return
        }
        let bindings = dict["bindings"] as? [[String: Any]]
        XCTAssertNotNil(bindings)
        XCTAssertGreaterThan(bindings?.count ?? 0, 0, "Should list properties from testStore")
    }

    func testBindingsGetIncludesStoreAndProperty() async throws {
        let result = try await transport.call("bindings.get")
        guard let dict = result as? [String: Any],
              let bindings = dict["bindings"] as? [[String: Any]] else {
            XCTFail("Expected bindings array"); return
        }

        let storeNames = Set(bindings.compactMap { $0["store"] as? String })
        XCTAssertTrue(storeNames.contains("testStore"))

        let paths = Set(bindings.compactMap { $0["path"] as? String })
        XCTAssertFalse(paths.isEmpty)
    }

    func testBindingsGetReturnsStoresList() async throws {
        let result = try await transport.call("bindings.get")
        guard let dict = result as? [String: Any] else {
            XCTFail("Expected dictionary result"); return
        }
        let stores = dict["stores"] as? [String]
        XCTAssertNotNil(stores)
        XCTAssertTrue(stores?.contains("testStore") == true)
    }

    // MARK: - timeline.get

    func testTimelineGetIsRegistered() {
        XCTAssertNotNil(transport.handlers["timeline.get"])
    }

    func testTimelineGetReturnsEntriesAndTotal() async throws {
        let result = try await transport.call("timeline.get", params: [:])
        guard let dict = result as? [String: Any] else {
            XCTFail("Expected dictionary result"); return
        }
        let entries = dict["entries"] as? [[String: Any]]
        let total = dict["total"] as? Int
        XCTAssertNotNil(entries)
        XCTAssertNotNil(total)
        XCTAssertGreaterThanOrEqual(total ?? 0, 0)
    }

    // MARK: - timeline.stats

    func testTimelineStatsIsRegistered() {
        XCTAssertNotNil(transport.handlers["timeline.stats"])
    }

    func testTimelineStatsReturnsTotalEntriesAndRates() async throws {
        let result = try await transport.call("timeline.stats", params: [:])
        guard let dict = result as? [String: Any] else {
            XCTFail("Expected dictionary result"); return
        }
        XCTAssertNotNil(dict["totalEntries"])
        XCTAssertNotNil(dict["windowMs"])
        XCTAssertNotNil(dict["rates"])
    }
}

#endif
