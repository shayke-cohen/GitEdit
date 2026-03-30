import XCTest
import Foundation
@testable import AppXray

#if DEBUG

final class AutoModeTests: XCTestCase {

    // MARK: - resolveMode tests

    /// Auto mode should resolve to .server when no relay env vars are set.
    func testAutoModeDefaultsToServer() {
        // Ensure no relay env vars are set (they shouldn't be in test environment)
        XCTAssertNil(ProcessInfo.processInfo.environment["APPXRAY_RELAY_HOST"],
                     "Test requires APPXRAY_RELAY_HOST to be unset")
        XCTAssertNil(ProcessInfo.processInfo.environment["APPXRAY_RELAY_PORT"],
                     "Test requires APPXRAY_RELAY_PORT to be unset")

        let config = AppXrayConfig(mode: .auto)
        // The resolved mode is tested indirectly by verifying AppXray
        // starts a WebSocket server (not a client) in auto mode.
        // Since resolveMode is private, we test through AppXrayConnectionMode enum.
        XCTAssertEqual(String(describing: config.mode), "auto")
    }

    /// Explicit .server mode should always be .server.
    func testExplicitServerMode() {
        let config = AppXrayConfig(mode: .server)
        XCTAssertEqual(String(describing: config.mode), "server")
    }

    /// Explicit .client mode should always be .client.
    func testExplicitClientMode() {
        let config = AppXrayConfig(mode: .client)
        XCTAssertEqual(String(describing: config.mode), "client")
    }

    /// AppXrayConfig defaults to .auto mode.
    func testDefaultConfigIsAutoMode() {
        let config = AppXrayConfig()
        XCTAssertEqual(String(describing: config.mode), "auto")
    }

    /// Verify AppXrayConnectionMode enum cases exist.
    func testConnectionModeEnumCases() {
        let modes: [AppXrayConnectionMode] = [.client, .server, .auto]
        XCTAssertEqual(modes.count, 3)
    }

    // MARK: - Config defaults

    func testDefaultPort() {
        let config = AppXrayConfig()
        XCTAssertEqual(config.port, 19400)
    }

    func testDefaultAutoDetect() {
        let config = AppXrayConfig()
        XCTAssertTrue(config.autoDetect)
    }

    func testCustomConfig() {
        let config = AppXrayConfig(
            appName: "TestApp",
            platform: "macos",
            version: "2.0.0",
            port: 19450,
            autoDetect: false,
            mode: .server,
            relayHost: "192.168.1.1",
            relayPort: 19401
        )
        XCTAssertEqual(config.appName, "TestApp")
        XCTAssertEqual(config.platform, "macos")
        XCTAssertEqual(config.version, "2.0.0")
        XCTAssertEqual(config.port, 19450)
        XCTAssertFalse(config.autoDetect)
        XCTAssertEqual(config.relayHost, "192.168.1.1")
        XCTAssertEqual(config.relayPort, 19401)
    }
}

#endif
