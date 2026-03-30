import XCTest
import Foundation
import Network
@testable import AppXray

#if DEBUG

final class WebSocketServerTests: XCTestCase {

    // MARK: - sendPong frame format (RFC 6455)

    func testSendPongFrameHasNoMaskBit() async throws {
        let port: UInt16 = 19490
        let appInfo: [String: Any] = [
            "appId": "test-pong", "name": "PongTest", "platform": "macos",
            "framework": "swiftui", "version": "1.0.0", "bundleId": "test",
            "port": Int(port), "host": "127.0.0.1", "pid": 1,
            "sdkVersion": "0.1.0", "capabilities": [] as [String],
            "startedAt": Int(Date().timeIntervalSince1970 * 1000),
        ]
        let server = WebSocketServer(port: port, appInfo: appInfo)
        server.start()

        try await Task.sleep(nanoseconds: 500_000_000)

        let (pongFrame, connection) = try await connectAndPing(port: port)
        connection.cancel()
        server.stop()

        // Verify pong frame format
        XCTAssertGreaterThanOrEqual(pongFrame.count, 2, "Pong frame too short")

        let firstByte = pongFrame[0]
        let secondByte = pongFrame[1]

        // FIN bit set + opcode 0xA (pong)
        XCTAssertEqual(firstByte & 0x80, 0x80, "FIN bit should be set")
        XCTAssertEqual(firstByte & 0x0F, 0x0A, "Opcode should be 0xA (pong)")

        // Mask bit MUST NOT be set (RFC 6455 Section 5.1)
        XCTAssertEqual(secondByte & 0x80, 0, "Server MUST NOT mask frames (RFC 6455)")
    }

    func testHttpUpgradeReturns101() async throws {
        let port: UInt16 = 19491
        let appInfo: [String: Any] = [
            "appId": "test-upgrade", "name": "UpgradeTest", "platform": "macos",
            "framework": "swiftui", "version": "1.0.0", "bundleId": "test",
            "port": Int(port), "host": "127.0.0.1", "pid": 1,
            "sdkVersion": "0.1.0", "capabilities": [] as [String],
            "startedAt": Int(Date().timeIntervalSince1970 * 1000),
        ]
        let server = WebSocketServer(port: port, appInfo: appInfo)
        server.start()

        try await Task.sleep(nanoseconds: 500_000_000)

        let response = try await sendRawHttpUpgrade(port: port)
        server.stop()

        XCTAssertTrue(response.hasPrefix("HTTP/1.1 101"), "Expected 101 Switching Protocols, got: \(response.prefix(50))")
        XCTAssertTrue(response.contains("Upgrade: websocket"), "Missing Upgrade header")
        XCTAssertTrue(response.contains("Sec-WebSocket-Accept:"), "Missing Accept header")
    }

    func testHttpUpgradeResponseIsNotFramed() async throws {
        let port: UInt16 = 19492
        let appInfo: [String: Any] = [
            "appId": "test-raw", "name": "RawTest", "platform": "macos",
            "framework": "swiftui", "version": "1.0.0", "bundleId": "test",
            "port": Int(port), "host": "127.0.0.1", "pid": 1,
            "sdkVersion": "0.1.0", "capabilities": [] as [String],
            "startedAt": Int(Date().timeIntervalSince1970 * 1000),
        ]
        let server = WebSocketServer(port: port, appInfo: appInfo)
        server.start()

        try await Task.sleep(nanoseconds: 500_000_000)

        let rawBytes = try await sendRawHttpUpgradeBytes(port: port)
        server.stop()

        // First byte of a WebSocket frame would be 0x81 (text) or 0x82 (binary).
        // Raw HTTP response starts with 'H' (0x48) for "HTTP/1.1".
        XCTAssertEqual(rawBytes[0], 0x48, "First byte should be 'H' (raw HTTP), not a WebSocket frame opcode")
    }

    // MARK: - Helpers

    private func connectAndPing(port: UInt16) async throws -> (Data, NWConnection) {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)

        return try await withCheckedThrowingContinuation { continuation in
            connection.start(queue: .global())

            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }

                let wsKey = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
                let upgrade = "GET / HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(wsKey)\r\nSec-WebSocket-Version: 13\r\n\r\n"
                connection.send(content: upgrade.data(using: .utf8), completion: .contentProcessed { _ in })

                var buffer = Data()
                var upgraded = false

                func doRead() {
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                        guard let data = data else { return }
                        buffer.append(data)

                        if !upgraded {
                            if let str = String(data: buffer, encoding: .utf8), str.contains("\r\n\r\n") {
                                upgraded = true
                                let headerEnd = str.range(of: "\r\n\r\n")!.upperBound
                                let headerBytes = str[str.startIndex..<headerEnd].utf8.count
                                buffer = Data(buffer.dropFirst(headerBytes))

                                // Send ping: FIN + opcode 0x9, masked, length 4, mask + payload
                                var ping = Data()
                                ping.append(0x89) // FIN + ping
                                ping.append(0x84) // masked + length 4
                                ping.append(contentsOf: [0, 0, 0, 0]) // mask
                                ping.append(contentsOf: [0x70, 0x69, 0x6E, 0x67]) // "ping"
                                connection.send(content: ping, completion: .contentProcessed { _ in })
                            }
                            doRead()
                            return
                        }

                        // Look for pong frame (opcode 0xA)
                        if buffer.count >= 2 && (buffer[0] & 0x0F) == 0x0A {
                            continuation.resume(returning: (buffer, connection))
                            return
                        }
                        doRead()
                    }
                }
                doRead()
            }
        }
    }

    private func sendRawHttpUpgrade(port: UInt16) async throws -> String {
        let bytes = try await sendRawHttpUpgradeBytes(port: port)
        return String(data: Data(bytes), encoding: .utf8) ?? ""
    }

    private func sendRawHttpUpgradeBytes(port: UInt16) async throws -> Data {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)

        return try await withCheckedThrowingContinuation { continuation in
            connection.start(queue: .global())

            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }

                let wsKey = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
                let upgrade = "GET / HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(wsKey)\r\nSec-WebSocket-Version: 13\r\n\r\n"
                connection.send(content: upgrade.data(using: .utf8), completion: .contentProcessed { _ in })

                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    connection.cancel()
                    if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                    }
                }
            }
        }
    }
}

#endif
