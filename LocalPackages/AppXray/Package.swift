// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppXray",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "AppXray", targets: ["AppXray"]),
    ],
    targets: [
        .target(
            name: "AppXray",
            path: "Sources/AppXray",
            exclude: [],
            swiftSettings: [.define("DEBUG")]
        ),
        .testTarget(
            name: "AppXrayTests",
            dependencies: ["AppXray"],
            path: "Tests/AppXrayTests",
            swiftSettings: [.define("DEBUG")]
        ),
    ]
)
