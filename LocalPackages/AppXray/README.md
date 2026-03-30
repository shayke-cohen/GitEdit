# AppXray — iOS/macOS SDK

Swift Package that gives AI coding agents inside-out access to your iOS and macOS apps via WebSocket.

## Requirements

- iOS 16+ / macOS 13+
- Swift 5.9+
- Xcode 15+

## Installation

Add as a Swift Package dependency:

```
https://github.com/your-org/appxray
```

Or add the package locally:

1. In Xcode: **File → Add Package Dependencies**
2. Enter the repository URL or select the local `packages/sdk-ios` folder
3. Add `AppXray` to your app target

## Quick Start

```swift
import AppXray

@main
struct MyApp: App {
    init() {
        #if DEBUG
        AppXray.shared.start(config: AppXrayConfig(
            appName: "MyApp",
            platform: AppXrayConfig.ios,  // or AppXrayConfig.macos
            version: "1.0.0",
            port: 19400
        ))
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

The SDK prints an auth token to the console. The MCP server uses this token when connecting.

## Configuration

| Parameter   | Type   | Default  | Description                              |
|------------|--------|----------|------------------------------------------|
| `appName`  | String | —        | Display name of your app                 |
| `platform` | String | `"ios"`  | `"ios"` or `"macos"`                     |
| `version`  | String | `"1.0.0"`| App version                              |
| `port`     | Int    | `19400`  | WebSocket listen port (19400–19499)      |
| `autoDetect` | Bool | `true`   | Reserved for future use                  |

## State Tracking

Register `ObservableObject` instances for state inspection and time-travel:

```swift
AppXray.shared.registerObservableObject(myViewModel, name: "main")
```

## Error Capture

Capture errors for inspection via `errors.list`:

```swift
AppXray.shared.captureError(error, context: "Login flow")
```

## Supported Methods

The SDK handles all appxray JSON-RPC methods:

- **Connect**: `appxray.handshake`, `appxray.info`, `appxray.authenticate`
- **Component**: `component.tree`, `component.trigger`, `component.input`
- **State**: `state.get`, `state.set`
- **Network**: `network.list`, `network.mock`
- **Storage**: `storage.read`, `storage.write`, `storage.clear`
- **Navigation**: `navigation.state`, `navigation.execute`
- **Errors**: `errors.list`
- **Time travel**: `timetravel.checkpoint`, `timetravel.restore`, `timetravel.history`
- **Chaos**: `chaos.start`, `chaos.stop`, `chaos.list`
- **Runtime**: `runtime.eval` (stub; Swift has no dynamic eval)

## Build

```bash
cd packages/sdk-ios
swift build
```

## Debug Only

The SDK is active only in DEBUG builds. In Release, `start()`, `shutdown()`, `registerObservableObject()`, and `captureError()` are no-ops.
