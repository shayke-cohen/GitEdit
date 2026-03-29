// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GitEdit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GitEditCore", targets: ["GitEditCore"]),
    ],
    dependencies: [
        // git library dependency will be added here when git integration begins
    ],
    targets: [
        // Core library — all testable business logic
        .target(
            name: "GitEditCore",
            dependencies: [],
            path: "GitEditCore"
        ),
        // Unit tests for core logic
        .testTarget(
            name: "GitEditTests",
            dependencies: ["GitEditCore"],
            path: "GitEditTests"
        ),
    ]
)
