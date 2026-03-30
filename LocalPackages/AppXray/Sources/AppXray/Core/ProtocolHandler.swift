import Foundation

// MARK: - AppXrayTransport

/// Shared protocol for both WebSocketServer and WebSocketClient.
/// Allows ProtocolHandler to register JSON-RPC handlers on either transport.
protocol AppXrayTransport: AnyObject {
    func registerHandler(_ method: String, handler: @escaping @Sendable ([String: Any]) async throws -> Any)
    func sendNotification(_ method: String, params: [String: Any]?)
}

extension WebSocketServer: AppXrayTransport {}
extension WebSocketClient: AppXrayTransport {}

// MARK: - ProtocolHandler

final class ProtocolHandler {
    private let componentInspector: ComponentInspector
    private let stateBridge: StateBridge
    private let networkInterceptor: NetworkInterceptor
    private let storageBridge: StorageBridge
    private let navigationBridge: NavigationBridge
    private let timeTravelEngine: TimeTravelEngine
    private let chaosEngine: ChaosEngine
    private let errorBuffer: ErrorBuffer
    private let consoleBridge: ConsoleBridge
    private let selectorEngine: SelectorEngine
    private let interactionEngine: InteractionEngine
    private let screenshotEngine: ScreenshotEngine
    private let waitEngine: WaitEngine
    private let recordEngine: RecordEngine
    private let timeline: TimelineBridge

    init(
        componentInspector: ComponentInspector,
        stateBridge: StateBridge,
        networkInterceptor: NetworkInterceptor,
        storageBridge: StorageBridge,
        navigationBridge: NavigationBridge,
        timeTravelEngine: TimeTravelEngine,
        chaosEngine: ChaosEngine,
        errorBuffer: ErrorBuffer,
        consoleBridge: ConsoleBridge,
        selectorEngine: SelectorEngine,
        interactionEngine: InteractionEngine,
        screenshotEngine: ScreenshotEngine,
        waitEngine: WaitEngine,
        recordEngine: RecordEngine,
        timeline: TimelineBridge
    ) {
        self.componentInspector = componentInspector
        self.stateBridge = stateBridge
        self.networkInterceptor = networkInterceptor
        self.storageBridge = storageBridge
        self.navigationBridge = navigationBridge
        self.timeTravelEngine = timeTravelEngine
        self.chaosEngine = chaosEngine
        self.errorBuffer = errorBuffer
        self.consoleBridge = consoleBridge
        self.selectorEngine = selectorEngine
        self.interactionEngine = interactionEngine
        self.screenshotEngine = screenshotEngine
        self.waitEngine = waitEngine
        self.recordEngine = recordEngine
        self.timeline = timeline
    }

    func registerHandlers(on server: AppXrayTransport) {
        server.registerHandler("component.tree") { [weak self] params in
            try await self?.componentInspector.getTree(params: params) ?? [:]
        }
        server.registerHandler("component.trigger") { [weak self] params in
            try await self?.componentInspector.triggerHandler(params: params) ?? [:]
        }
        server.registerHandler("component.input") { [weak self] params in
            try await self?.componentInspector.input(params: params) ?? [:]
        }
        server.registerHandler("state.get") { [weak self] params in
            guard let self = self else { return [:] }
            let path = params["path"] as? String ?? ""
            let depth = params["depth"] as? Int
            return await MainActor.run { self.stateBridge.get(path: path, depth: depth) ?? [:] }
        }
        server.registerHandler("state.set") { [weak self] params in
            guard let self = self else { return [:] }
            let path = params["path"] as? String ?? ""
            guard let value = params["value"] else { throw AppXrayError.invalidParams("value required") }
            let merge = params["merge"] as? Bool
            return await MainActor.run { self.stateBridge.set(path: path, value: value, merge: merge) ?? [:] }
        }
        server.registerHandler("network.list") { [weak self] params in
            try await self?.networkInterceptor.list(params: params) ?? [:]
        }
        server.registerHandler("network.mock") { [weak self] params in
            try await self?.networkInterceptor.mock(params: params) ?? [:]
        }
        server.registerHandler("storage.read") { [weak self] params in
            try await self?.storageBridge.read(params: params) ?? [:]
        }
        server.registerHandler("storage.write") { [weak self] params in
            try await self?.storageBridge.write(params: params) ?? [:]
        }
        server.registerHandler("storage.clear") { [weak self] params in
            try await self?.storageBridge.clear(params: params) ?? [:]
        }
        server.registerHandler("navigation.state") { [weak self] _ in
            await MainActor.run { self?.navigationBridge.getState() ?? [:] }
        }
        server.registerHandler("navigation.execute") { [weak self] params in
            try await self?.navigationBridge.execute(params: params) ?? [:]
        }
        server.registerHandler("errors.list") { [weak self] params in
            guard let self = self else { return ["errors": []] as [String: Any] }
            let type = params["type"] as? String
            let limit = params["limit"] as? Int
            let since = params["since"] as? TimeInterval
            let clear = params["clear"] as? Bool ?? false
            let entries = self.errorBuffer.list(type: type, limit: limit, since: since, clear: clear)
            return ["errors": entries] as [String: Any]
        }
        server.registerHandler("console.list") { [weak self] params in
            guard let self = self else { return ["entries": []] as [String: Any] }
            let level = params["level"] as? String
            let limit = params["limit"] as? Int
            let since = params["since"] as? TimeInterval
            let clear = params["clear"] as? Bool ?? false
            let entries = self.consoleBridge.list(level: level, limit: limit, since: since, clear: clear)
            return ["entries": entries] as [String: Any]
        }
        server.registerHandler("timetravel.checkpoint") { [weak self] params in
            try await self?.timeTravelEngine.createCheckpoint(params: params) ?? [:]
        }
        server.registerHandler("timetravel.restore") { [weak self] params in
            try await self?.timeTravelEngine.restoreCheckpoint(params: params) ?? [:]
        }
        server.registerHandler("timetravel.history") { [weak self] params in
            try await self?.timeTravelEngine.getHistory(params: params) ?? [:]
        }
        server.registerHandler("chaos.start") { [weak self] params in
            try await self?.chaosEngine.start(params: params) ?? [:]
        }
        server.registerHandler("chaos.stop") { [weak self] params in
            try await self?.chaosEngine.stop(params: params) ?? [:]
        }
        server.registerHandler("chaos.list") { [weak self] _ in
            self?.chaosEngine.list() ?? [:]
        }
        server.registerHandler("runtime.eval") { [weak self] params in
            try await self?.eval(params: params) ?? [:]
        }

        server.registerHandler("schema.get") { [weak self] params in
            guard let self = self else { return [:] }
            let path = params["path"] as? String ?? ""
            return await MainActor.run { self.getSchema(path: path) }
        }

        server.registerHandler("metrics.get") { [weak self] _ in
            guard let self = self else { return [:] }
            return self.getMetrics()
        }

        server.registerHandler("bindings.get") { [weak self] params in
            guard let self = self else { return [:] }
            return await MainActor.run { self.getBindings(params: params) }
        }

        // Interaction & Automation
        server.registerHandler("selector.resolve") { [weak self] params in
            await MainActor.run { self?.selectorEngine.resolve(params: params) ?? ["found": false, "matches": 0] }
        }
        server.registerHandler("interaction.tap") { [weak self] params in
            try await self?.interactionEngine.tap(params: params) ?? [:]
        }
        server.registerHandler("interaction.doubleTap") { [weak self] params in
            var p = params; p["count"] = 2
            return try await self?.interactionEngine.tap(params: p) ?? [:]
        }
        server.registerHandler("interaction.longPress") { [weak self] params in
            try await self?.interactionEngine.longPress(params: params) ?? [:]
        }
        server.registerHandler("interaction.type") { [weak self] params in
            try await self?.interactionEngine.typeText(params: params) ?? [:]
        }
        server.registerHandler("interaction.swipe") { [weak self] params in
            try await self?.interactionEngine.swipe(params: params) ?? [:]
        }
        server.registerHandler("interaction.drag") { [weak self] params in
            try await self?.interactionEngine.drag(params: params) ?? [:]
        }
        server.registerHandler("screenshot.capture") { [weak self] params in
            try await self?.screenshotEngine.capture(params: params) ?? [:]
        }
        server.registerHandler("wait.for") { [weak self] params in
            try await self?.waitEngine.waitFor(params: params) ?? [:]
        }
        server.registerHandler("record.start") { [weak self] _ in
            await MainActor.run { self?.recordEngine.start() ?? ["started": false] }
        }
        server.registerHandler("record.stop") { [weak self] _ in
            await MainActor.run { self?.recordEngine.stop() ?? [:] }
        }
        server.registerHandler("record.events") { [weak self] params in
            await MainActor.run { self?.recordEngine.getEvents(params: params) ?? [:] }
        }

        server.registerHandler("timeline.get") { [weak self] params in
            guard let self = self else { return ["entries": [], "total": 0] as [String: Any] }
            let since = params["since"] as? Double
            let category = (params["category"] as? String).flatMap { TimelineCategory(rawValue: $0) }
            let limit = params["limit"] as? Int ?? 100
            let search = params["search"] as? String
            let result = self.timeline.get(since: since, category: category, limit: limit, search: search)
            let entriesDicts = result.entries.compactMap { Self.encodeTimelineEntry($0) }
            return ["entries": entriesDicts, "total": result.total] as [String: Any]
        }

        server.registerHandler("timeline.stats") { [weak self] params in
            guard let self = self else { return [:] }
            let windowMs = params["windowMs"] as? Int ?? 60_000
            let stats = self.timeline.stats(windowMs: windowMs)
            return [
                "totalEntries": stats.totalEntries,
                "windowMs": stats.windowMs,
                "rates": stats.rates,
            ] as [String: Any]
        }
    }

    private static func encodeTimelineEntry(_ entry: TimelineEntry) -> [String: Any]? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(entry),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }

    private func eval(params: [String: Any]) async throws -> [String: Any] {
        _ = params["expression"] as? String
        return [
            "result": NSNull(),
            "error": "runtime.eval not available in Swift (no dynamic eval)",
        ] as [String: Any]
    }

    // MARK: - Schema

    private func getSchema(path: String) -> [String: Any] {
        let stores = stateBridge.listStores()
        if path.isEmpty {
            var schemas: [String: Any] = [:]
            for store in stores {
                if let stateData = stateBridge.get(path: store, depth: 1),
                   let value = stateData["value"] {
                    schemas[store] = buildSchema(from: value)
                }
            }
            return ["schema": schemas, "stores": stores]
        }

        if let stateData = stateBridge.get(path: path, depth: 2),
           let value = stateData["value"] {
            return ["schema": buildSchema(from: value), "path": path]
        }
        return ["schema": [:] as [String: Any], "path": path]
    }

    private func buildSchema(from value: Any) -> [String: Any] {
        switch value {
        case let dict as [String: Any]:
            if let type = dict["type"] as? String, dict["value"] != nil {
                return ["type": type]
            }
            var properties: [String: Any] = [:]
            for (key, val) in dict {
                properties[key] = buildSchema(from: val)
            }
            return ["type": "object", "properties": properties]
        case let arr as [Any]:
            let itemSchema = arr.first.map { buildSchema(from: $0) } ?? ["type": "unknown"]
            return ["type": "array", "items": itemSchema, "length": arr.count]
        case is String: return ["type": "string"]
        case is Int, is Double, is Float: return ["type": "number"]
        case is Bool: return ["type": "boolean"]
        default: return ["type": String(describing: type(of: value))]
        }
    }

    // MARK: - Metrics

    private func getMetrics() -> [String: Any] {
        var result: [String: Any] = [:]

        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            result["memory"] = [
                "resident": info.resident_size,
                "virtual": info.virtual_size,
            ] as [String: Any]
        }

        result["uptime"] = ProcessInfo.processInfo.systemUptime
        result["processorCount"] = ProcessInfo.processInfo.processorCount
        result["thermalState"] = thermalStateName(ProcessInfo.processInfo.thermalState)

        return result
    }

    private func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Bindings

    private func getBindings(params: [String: Any]) -> [String: Any] {
        let stores = stateBridge.listStores()
        var bindings: [[String: Any]] = []
        for store in stores {
            if let stateData = stateBridge.get(path: store, depth: 1),
               let value = stateData["value"] as? [String: Any] {
                for key in value.keys {
                    bindings.append([
                        "store": store,
                        "property": key,
                        "path": "\(store).\(key)",
                    ])
                }
            }
        }
        return ["bindings": bindings, "stores": stores]
    }
}

enum AppXrayError: Error, LocalizedError {
    case invalidParams(String)
    case methodNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidParams(let msg): return msg
        case .methodNotFound(let msg): return "Method not found: \(msg)"
        }
    }
}
