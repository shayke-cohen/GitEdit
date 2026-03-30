import Foundation
import Combine

#if DEBUG

// MARK: - AppXrayConnectionMode

public enum AppXrayConnectionMode: Sendable {
    case client
    case server
    case auto
}

// MARK: - AppXrayConfig

public struct AppXrayConfig: Sendable {
    public let appName: String?
    public let platform: String?
    public let version: String
    public let port: Int
    public let autoDetect: Bool
    public let mode: AppXrayConnectionMode
    public let relayHost: String?
    public let relayPort: Int?

    public init(
        appName: String? = nil,
        platform: String? = nil,
        version: String = "1.0.0",
        port: Int = 19400,
        autoDetect: Bool = true,
        mode: AppXrayConnectionMode = .auto,
        relayHost: String? = nil,
        relayPort: Int? = nil
    ) {
        self.appName = appName
        self.platform = platform
        self.version = version
        self.port = port
        self.autoDetect = autoDetect
        self.mode = mode
        self.relayHost = relayHost
        self.relayPort = relayPort
    }

    public static var ios: String { "ios" }
    public static var macos: String { "macos" }
}

// MARK: - AppXray

/// Main entry point for the appxray iOS/macOS SDK.
/// Provides inside-out access to app internals via WebSocket for AI coding agents.
@MainActor
public final class AppXray: ObservableObject {
    public static let shared = AppXray()

    private var webSocketServer: WebSocketServer?
    private var webSocketClient: WebSocketClient?
    private let protocolHandler: ProtocolHandler
    private let componentInspector: ComponentInspector
    private let stateBridge: StateBridge
    private let networkInterceptor: NetworkInterceptor
    private let storageBridge: StorageBridge
    private let navigationBridge: NavigationBridge
    private let timeTravelEngine: TimeTravelEngine
    private let chaosEngine: ChaosEngine
    internal let timelineBridge = TimelineBridge()
    private let errorBuffer: ErrorBuffer
    private let consoleBridge = ConsoleBridge()
    private let selectorEngine: SelectorEngine
    private let interactionEngine: InteractionEngine
    private let screenshotEngine: ScreenshotEngine
    private let waitEngine: WaitEngine
    private let recordEngine: RecordEngine

    private var isStarted = false
    private let queue = DispatchQueue(label: "com.appxray.sdk", qos: .userInitiated)

    private init() {
        self.componentInspector = ComponentInspector()
        self.stateBridge = StateBridge()
        self.networkInterceptor = NetworkInterceptor(timeline: timelineBridge)
        self.storageBridge = StorageBridge()
        self.navigationBridge = NavigationBridge()
        self.timeTravelEngine = TimeTravelEngine(stateBridge: stateBridge, navigationBridge: navigationBridge)
        self.chaosEngine = ChaosEngine(networkInterceptor: networkInterceptor)
        self.selectorEngine = SelectorEngine()
        self.interactionEngine = InteractionEngine(selectorEngine: selectorEngine)
        self.screenshotEngine = ScreenshotEngine()
        self.waitEngine = WaitEngine(selectorEngine: selectorEngine, networkInterceptor: networkInterceptor, stateBridge: stateBridge)
        self.recordEngine = RecordEngine(selectorEngine: selectorEngine)
        self.errorBuffer = ErrorBuffer(timeline: timelineBridge)
        self.protocolHandler = ProtocolHandler(
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
            timeline: timelineBridge
        )
    }

    /// Initialize and start the SDK with default config. Only active in DEBUG builds.
    /// Reads appName from CFBundleDisplayName and auto-detects platform.
    public func start(appName: String? = nil) {
        start(config: AppXrayConfig(appName: appName))
    }

    /// Initialize and start the SDK. Only active in DEBUG builds.
    public func start(config: AppXrayConfig) {
        #if DEBUG
        guard !isStarted else { return }
        isStarted = true

        let port: UInt16
        if let envPort = ProcessInfo.processInfo.environment["APPXRAY_SERVER_PORT"],
           let parsed = UInt16(envPort) {
            port = parsed
        } else {
            port = UInt16(config.port)
        }
        let bundleId = Bundle.main.bundleIdentifier
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String
            ?? ProcessInfo.processInfo.processName
        let resolvedAppName = config.appName ?? Self.inferAppName()
        let resolvedPlatform = config.platform ?? Self.inferPlatform()
        let appInfo: [String: Any] = [
            "appId": "\(bundleId)-\(ProcessInfo.processInfo.processIdentifier)",
            "name": resolvedAppName,
            "platform": resolvedPlatform,
            "framework": "swiftui",
            "version": config.version,
            "bundleId": bundleId,
            "port": Int(port),
            "host": "127.0.0.1",
            "pid": ProcessInfo.processInfo.processIdentifier,
            "sdkVersion": "0.1.0",
            "capabilities": [
                "component-tree",
                "state-read",
                "state-write",
                "network-intercept",
                "storage-read",
                "storage-write",
                "navigation",
                "event-handlers",
                "time-travel",
                "chaos",
                "eval",
                "accessibility",
                "interaction",
                "screenshot",
                "record",
                "timeline",
            ],
            "startedAt": Int(Date().timeIntervalSince1970 * 1000),
        ]

        let resolvedMode = resolveMode(config.mode)

        if resolvedMode == .client {
            let host = resolveRelayHost(explicit: config.relayHost)
            let relayPort = UInt16(resolveRelayPort(explicit: config.relayPort))
            let client = WebSocketClient(relayHost: host, relayPort: relayPort, appInfo: appInfo)
            protocolHandler.registerHandlers(on: client)
            client.start()
            webSocketClient = client
            print("[appxray] Client mode — connecting to relay at \(host):\(relayPort)")
        } else {
            let server = WebSocketServer(port: port, appInfo: appInfo)
            protocolHandler.registerHandlers(on: server)
            server.start()
            webSocketServer = server
            print("[appxray] Server mode — listening on port \(port)")
            print("[appxray] Auth token: \(server.authToken)")
        }

        networkInterceptor.install()
        consoleBridge.startCapture()
        #endif
    }

    /// Shutdown the SDK and release resources.
    public func shutdown() {
        #if DEBUG
        webSocketServer?.stop()
        webSocketServer = nil
        webSocketClient?.stop()
        webSocketClient = nil
        networkInterceptor.uninstall()
        consoleBridge.stopCapture()
        isStarted = false
        #endif
    }

    /// Register an ObservableObject for state tracking and time-travel.
    public func registerObservableObject(_ obj: Any, name: String) {
        #if DEBUG
        stateBridge.registerObservable(obj, name: name)
        #endif
    }

    public func bindSelection(
        getCurrent: @escaping () -> String?,
        setSelection: @escaping (String) -> Void,
        getAvailable: @escaping () -> [String]
    ) {
        #if DEBUG
        navigationBridge.bindSelection(NavigationBridge.SelectionBinding(
            getCurrent: getCurrent,
            setSelection: setSelection,
            getAvailable: getAvailable
        ))
        #endif
    }

    /// Bind a SwiftUI NavigationPath for stack-based navigation.
    public func bindNavigationPath(
        getStack: @escaping () -> [String],
        push: @escaping (String) -> Void,
        pop: @escaping () -> Void,
        replace: @escaping (String) -> Void
    ) {
        #if DEBUG
        navigationBridge.bindSwiftUIPath(NavigationBridge.NavigationPathBinding(
            getStack: getStack,
            push: push,
            pop: pop,
            replace: replace
        ))
        #endif
    }

    /// Register an ObservableObject with explicit setters for properties that can't
    /// be set via KVC (Swift enums, structs, etc.).
    public func registerObservableObject(_ obj: Any, name: String, setters: [String: (Any) -> Void]) {
        #if DEBUG
        stateBridge.registerObservable(obj, name: name, setters: setters)
        #endif
    }

    /// Log a message for inspection via inspect(target: "logs").
    /// Use this for messages that go through os_log/Logger since those bypass
    /// the stdout/stderr pipe capture.
    public func log(_ message: String, level: String = "log") {
        #if DEBUG
        consoleBridge.log(message, level: level)
        #endif
    }

    /// Capture an error for later inspection via errors.list.
    public func captureError(_ error: Error, context: String? = nil) {
        #if DEBUG
        errorBuffer.capture(error, context: context)
        #endif
    }

    // MARK: - Auto-Detection

    private static func inferAppName() -> String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !displayName.isEmpty {
            return displayName
        }
        if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !bundleName.isEmpty {
            return bundleName
        }
        return "app"
    }

    private static func inferPlatform() -> String {
        #if os(macOS)
        return "macos"
        #else
        return "ios"
        #endif
    }

    // MARK: - Relay Address Resolution

    private func resolveRelayHost(explicit: String?) -> String {
        if let explicit = explicit { return explicit }
        if let envHost = ProcessInfo.processInfo.environment["APPXRAY_RELAY_HOST"] {
            return envHost
        }
        return "127.0.0.1"
    }

    private func resolveRelayPort(explicit: Int?) -> Int {
        if let explicit = explicit { return explicit }
        if let envPort = ProcessInfo.processInfo.environment["APPXRAY_RELAY_PORT"],
           let port = Int(envPort) {
            return port
        }
        return 19400
    }

    private func resolveMode(_ mode: AppXrayConnectionMode) -> AppXrayConnectionMode {
        switch mode {
        case .client, .server:
            return mode
        case .auto:
            if ProcessInfo.processInfo.environment["APPXRAY_RELAY_HOST"] != nil ||
               ProcessInfo.processInfo.environment["APPXRAY_RELAY_PORT"] != nil {
                return .client
            }
            return .server
        }
    }
}

#endif
