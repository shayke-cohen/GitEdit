import Foundation

#if DEBUG

/// WebSocket client that connects OUT to the appxray MCP relay server.
/// Uses URLSessionWebSocketTask for reliable bidirectional communication.
final class WebSocketClient: @unchecked Sendable {
    private let relayHost: String
    private let relayPort: UInt16
    private let appInfo: [String: Any]
    private let queue = DispatchQueue(label: "com.appxray.ws.client", qos: .userInitiated)

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var handlers: [String: @Sendable ([String: Any]) async throws -> Any] = [:]
    private var isConnected = false
    private var shouldReconnect = true

    let authToken: String

    init(relayHost: String, relayPort: UInt16, appInfo: [String: Any]) {
        self.relayHost = relayHost
        self.relayPort = relayPort
        self.appInfo = appInfo
        self.authToken = Self.generateToken()
    }

    private static func generateToken() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        var token = "appxray_"
        for _ in 0..<24 {
            token += String(chars.randomElement()!)
        }
        return token
    }

    func registerHandler(_ method: String, handler: @escaping @Sendable ([String: Any]) async throws -> Any) {
        queue.sync {
            handlers[method] = handler
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.connect()
        }
    }

    func stop() {
        shouldReconnect = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
    }

    // MARK: - Connection

    private func connect() {
        let url = URL(string: "ws://\(relayHost):\(relayPort)")!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        task = session?.webSocketTask(with: url)
        task?.resume()

        isConnected = true
        sendAnnounce()
        print("[appxray] Connected to relay at \(relayHost):\(relayPort)")
        print("[appxray] Auth token: \(authToken)")
        receiveNext()
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        isConnected = false
        queue.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.connect()
        }
    }

    // MARK: - Receive Loop

    private func receiveNext() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleJsonRpcMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleJsonRpcMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveNext()
            case .failure:
                self.scheduleReconnect()
            }
        }
    }

    // MARK: - Announce

    private func sendAnnounce() {
        let notification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "appxray.announce",
            "params": ["appInfo": appInfo],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: notification),
           let str = String(data: data, encoding: .utf8) {
            sendText(str)
        }
    }

    // MARK: - JSON-RPC

    private func handleJsonRpcMessage(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let hasId = json["id"] != nil
        let method = json["method"] as? String
        let params = json["params"] as? [String: Any] ?? [:]
        let reqId = json["id"]

        Task { @MainActor in
            do {
                if let method = method, hasId {
                    var result: Any?
                    if method == "appxray.handshake" {
                        result = self.appInfo
                    } else if method == "appxray.authenticate" {
                        let token = params["token"] as? String
                        result = ["authenticated": token == self.authToken]
                    } else if method == "appxray.info" {
                        result = self.appInfo
                    } else if let handler = self.getHandler(method) {
                        result = try await handler(params)
                    } else {
                        self.sendError(id: reqId, code: -32601, message: "Method not found: \(method)")
                        return
                    }
                    if let result = result {
                        self.sendResponse(id: reqId, result: result)
                    }
                }
            } catch {
                self.sendError(id: reqId, code: -32603, message: error.localizedDescription)
            }
        }
    }

    private func getHandler(_ method: String) -> (@Sendable ([String: Any]) async throws -> Any)? {
        queue.sync {
            handlers[method]
        }
    }

    private func sendResponse(id: Any?, result: Any) {
        var payload: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id = id { payload["id"] = id }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            sendText(str)
        }
    }

    private func sendError(id: Any?, code: Int, message: String) {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message],
        ]
        if let id = id { payload["id"] = id }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            sendText(str)
        }
    }

    func sendNotification(_ method: String, params: [String: Any]?) {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params as Any,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            sendText(str)
        }
    }

    private func sendText(_ text: String) {
        task?.send(.string(text)) { error in
            if error != nil {
                // Silently fail — reconnect will handle it
            }
        }
    }
}

#endif
