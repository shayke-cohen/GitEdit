import Foundation
import Network

#if DEBUG

// MARK: - WebSocketServer

/// WebSocket server using Network framework (NWListener).
/// Accepts connections, performs HTTP WebSocket upgrade, handles JSON-RPC 2.0 messages.
final class WebSocketServer: @unchecked Sendable {
    private let port: UInt16
    private let appInfo: [String: Any]
    private let queue = DispatchQueue(label: "com.appxray.ws", qos: .userInitiated)

    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var connectionHandlers: [UUID: (String) -> Void] = [:]
    private var handlers: [String: @Sendable ([String: Any]) async throws -> Any] = [:]
    private var isRunning = false

    let authToken: String

    init(port: UInt16, appInfo: [String: Any]) {
        self.port = port
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

    func start() {
        queue.async { [weak self] in
            self?.startInternal()
        }
    }

    private func startInternal() {
        guard !isRunning else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("[appxray] WebSocket server listening on port \(self?.port ?? 0)")
                    self?.registerPort()
                case .failed(let error):
                    print("[appxray] Listener failed: \(error)")
                case .cancelled:
                    break
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener.start(queue: queue)
            isRunning = true
        } catch {
            print("[appxray] Failed to start WebSocket server: \(error)")
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            for (_, conn) in self?.connections ?? [:] {
                conn.cancel()
            }
            self?.connections.removeAll()
            self?.connectionHandlers.removeAll()
            self?.isRunning = false
            self?.unregisterPort()
        }
    }

    deinit {
        #if DEBUG
        PortRegistry.remove(port: port)
        #endif
    }

    // MARK: - Port registry

    private func registerPort() {
        #if DEBUG
        let appId = appInfo["appId"] as? String ?? ""
        let appName = appInfo["name"] as? String ?? ""
        let platform = appInfo["platform"] as? String ?? ""
        PortRegistry.register(port: port, appId: appId, appName: appName, platform: platform)
        #endif
    }

    private func unregisterPort() {
        #if DEBUG
        PortRegistry.remove(port: port)
        #endif
    }

    func registerHandler(_ method: String, handler: @escaping @Sendable ([String: Any]) async throws -> Any) {
        queue.sync { [weak self] in
            self?.handlers[method] = handler
        }
    }

    func sendNotification(_ method: String, params: [String: Any]?) {
        queue.async { [weak self] in
            let payload: [String: Any] = [
                "jsonrpc": "2.0",
                "method": method,
                "params": params as Any,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let str = String(data: data, encoding: .utf8) {
                for (_, callback) in self?.connectionHandlers ?? [:] {
                    callback(str)
                }
            }
        }
    }

    // MARK: - Connection handling

    private final class ConnectionState {
        var buffer = Data()
        var upgradeComplete = false
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection
        connection.start(queue: queue)
        let state = ConnectionState()

        func doReceive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self = self else { return }
                if error != nil {
                    self.removeConnection(id)
                    return
                }
                if isComplete, data == nil {
                    self.removeConnection(id)
                    return
                }
                if let data = data {
                    state.buffer.append(data)
                    if !state.upgradeComplete {
                        if let (response, remainder) = self.handleHttpUpgrade(state.buffer) {
                            state.upgradeComplete = true
                            state.buffer = remainder
                            self.sendRaw(connection, data: response)
                            if !remainder.isEmpty {
                                self.processWebSocketFrames(connection, id: id, data: &state.buffer)
                            }
                        } else if state.buffer.count > 16384 {
                            self.removeConnection(id)
                            return
                        }
                    } else {
                        self.processWebSocketFrames(connection, id: id, data: &state.buffer)
                    }
                }
                switch connection.state {
                case .ready, .preparing:
                    doReceive()
                default:
                    break
                }
            }
        }
        doReceive()
    }

    private func removeConnection(_ id: UUID) {
        connections[id]?.cancel()
        connections.removeValue(forKey: id)
        connectionHandlers.removeValue(forKey: id)
    }

    // MARK: - HTTP upgrade

    private func handleHttpUpgrade(_ data: Data) -> (Data, Data)? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        guard str.contains("\r\n\r\n") else { return nil }

        let parts = str.components(separatedBy: "\r\n\r\n")
        let headerPart = parts[0]
        let bodyStart = (headerPart + "\r\n\r\n").data(using: .utf8)!.count
        let remainder = data.subdata(in: bodyStart..<data.count)

        let lines = headerPart.components(separatedBy: "\r\n")
        guard let first = lines.first, first.hasPrefix("GET ") else { return nil }

        var key: String?
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("sec-websocket-key:") {
                key = line.split(separator: ":", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespaces) }
            }
        }
        guard let secKey = key else { return nil }

        let acceptKey = createWebSocketAcceptKey(secKey)
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(acceptKey)\r
        \r

        """
        return (response.data(using: .utf8)!, remainder)
    }

    private func createWebSocketAcceptKey(_ key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + magic
        guard let data = combined.data(using: .utf8) else { return "" }
        return Data(SHA1.hash(data: data)).base64EncodedString()
    }

    // MARK: - WebSocket frames

    private func processWebSocketFrames(_ connection: NWConnection, id: UUID, data: inout Data) {
        while data.count >= 2 {
            let first = data[0]
            let second = data[1]
            let opcode = first & 0x0F
            let masked = (second & 0x80) != 0
            var payloadLen = Int(second & 0x7F)

            var headerSize = 2
            if payloadLen == 126 {
                if data.count < 4 { break }
                payloadLen = Int(data[2]) << 8 | Int(data[3])
                headerSize = 4
            } else if payloadLen == 127 {
                if data.count < 10 { break }
                payloadLen = 0
                for i in 0..<8 { payloadLen = (payloadLen << 8) | Int(data[2 + i]) }
                headerSize = 10
            }

            let maskOffset = masked ? 4 : 0
            let totalLen = headerSize + maskOffset + payloadLen
            if data.count < totalLen { break }

            var payload = data.subdata(in: (headerSize + maskOffset)..<totalLen)
            if masked {
                let mask = data.subdata(in: headerSize..<(headerSize + 4))
                for i in 0..<payload.count {
                    payload[i] ^= mask[i % 4]
                }
            }

            data = data.subdata(in: totalLen..<data.count)

            switch opcode {
            case 0x1: // text
                if let str = String(data: payload, encoding: .utf8) {
                    handleJsonRpcMessage(str, connection: connection, id: id)
                }
            case 0x8: // close
                removeConnection(id)
                return
            case 0x9: // ping
                sendPong(connection, payload: payload)
            default:
                break
            }
        }
    }

    private func sendPong(_ connection: NWConnection, payload: Data) {
        var frame = Data()
        frame.append(0x80 | 0xA) // FIN + pong opcode
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else {
            frame.append(126)
            frame.append(contentsOf: [UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)])
        }
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private static let handlerTimeoutSeconds: Double = 15.0

    /// Thread-safe one-shot guard ensuring exactly one response per request.
    private final class ResponseGuard: @unchecked Sendable {
        private var _responded = false
        private let lock = NSLock()

        func tryClaimResponse() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if _responded { return false }
            _responded = true
            return true
        }
    }

    private func handleJsonRpcMessage(_ raw: String, connection: NWConnection, id: UUID) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let hasId = json["id"] != nil
        let method = json["method"] as? String
        let params = json["params"] as? [String: Any] ?? [:]
        let reqId = json["id"]

        if let method = method, hasId {
            if method == "appxray.handshake" {
                self.sendResponse(connection, id: reqId, result: self.appInfo)
                return
            } else if method == "appxray.authenticate" {
                let token = params["token"] as? String
                self.sendResponse(connection, id: reqId, result: ["authenticated": token == self.authToken])
                return
            } else if method == "appxray.info" {
                self.sendResponse(connection, id: reqId, result: self.appInfo)
                return
            }

            guard let handler = self.getHandler(method) else {
                self.sendError(connection, id: reqId, code: -32601, message: "Method not found: \(method)")
                return
            }

            let guard_ = ResponseGuard()

            let timeoutWork = DispatchWorkItem { [weak self] in
                guard guard_.tryClaimResponse() else { return }
                self?.sendError(connection, id: reqId, code: -32001,
                    message: "Handler timed out after \(Self.handlerTimeoutSeconds)s for \(method). "
                           + "For macOS SwiftUI, try inspect(target:'state') or act(action:'navigate') as alternatives.")
            }
            queue.asyncAfter(deadline: .now() + Self.handlerTimeoutSeconds, execute: timeoutWork)

            let handlerTask = Task { @MainActor in
                do {
                    let result = try await handler(params)
                    self.queue.async {
                        timeoutWork.cancel()
                        guard guard_.tryClaimResponse() else { return }
                        self.sendResponse(connection, id: reqId, result: result)
                    }
                } catch {
                    self.queue.async {
                        timeoutWork.cancel()
                        guard guard_.tryClaimResponse() else { return }
                        self.sendError(connection, id: reqId, code: -32603, message: error.localizedDescription)
                    }
                }
            }

            timeoutWork.notify(queue: queue) {
                handlerTask.cancel()
            }
        }
    }

    private func getHandler(_ method: String) -> (@Sendable ([String: Any]) async throws -> Any)? {
        var handler: (@Sendable ([String: Any]) async throws -> Any)?
        queue.sync {
            handler = handlers[method]
        }
        return handler
    }

    private func sendResponse(_ connection: NWConnection, id: Any, result: Any) {
        let payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            send(connection, text: str)
        }
    }

    private func sendError(_ connection: NWConnection, id: Any?, code: Int, message: String) {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message],
        ]
        if let id = id {
            payload["id"] = id
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            send(connection, text: str)
        }
    }

    private func sendRaw(_ connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func send(_ connection: NWConnection, data: Data) {
        var frame = Data()
        frame.append(0x81) // text, fin
        if data.count < 126 {
            frame.append(UInt8(data.count))
        } else if data.count < 65536 {
            frame.append(126)
            frame.append(contentsOf: [UInt8(data.count >> 8), UInt8(data.count & 0xFF)])
        } else {
            frame.append(127)
            for i in (0..<8).reversed() {
                frame.append(UInt8((data.count >> (i * 8)) & 0xFF))
            }
        }
        frame.append(data)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func send(_ connection: NWConnection, text: String) {
        if let data = text.data(using: .utf8) {
            send(connection, data: data)
        }
    }

    // Store callback for notifications (used when we want to push to connected clients)
    func setMessageCallback(for id: UUID, _ callback: @escaping (String) -> Void) {
        queue.async { [weak self] in
            self?.connectionHandlers[id] = callback
        }
    }
}

// MARK: - SHA1

private enum SHA1 {
    static func hash(data: Data) -> [UInt8] {
        var message = Array(data)
        let bitLen = message.count * 8
        message.append(0x80)
        while (message.count % 64) != 56 {
            message.append(0)
        }
        for i in (0..<8).reversed() {
            message.append(UInt8((bitLen >> (i * 8)) & 0xFF))
        }

        var h0: UInt32 = 0x67452301, h1: UInt32 = 0xEFCDAB89, h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476, h4: UInt32 = 0xC3D2E1F0

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let j = chunkStart + i * 4
                w[i] = UInt32(message[j]) << 24 | UInt32(message[j+1]) << 16 | UInt32(message[j+2]) << 8 | UInt32(message[j+3])
            }
            for i in 16..<80 {
                w[i] = ((w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16]) << 1) | ((w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16]) >> 31)
            }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                var f: UInt32, k: UInt32
                switch i {
                case 0..<20:
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                let t = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = (b << 30) | (b >> 2)
                b = a
                a = t
            }
            h0 = (h0 &+ a) & 0xFFFFFFFF
            h1 = (h1 &+ b) & 0xFFFFFFFF
            h2 = (h2 &+ c) & 0xFFFFFFFF
            h3 = (h3 &+ d) & 0xFFFFFFFF
            h4 = (h4 &+ e) & 0xFFFFFFFF
        }
        func appendBytes(_ val: UInt32) -> [UInt8] {
            [
                UInt8((val >> 24) & 0xFF),
                UInt8((val >> 16) & 0xFF),
                UInt8((val >> 8) & 0xFF),
                UInt8(val & 0xFF),
            ]
        }
        var bytes: [UInt8] = []
        bytes.append(contentsOf: appendBytes(h0))
        bytes.append(contentsOf: appendBytes(h1))
        bytes.append(contentsOf: appendBytes(h2))
        bytes.append(contentsOf: appendBytes(h3))
        bytes.append(contentsOf: appendBytes(h4))
        return bytes
    }
}

#endif
