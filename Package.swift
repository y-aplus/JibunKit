// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JibunKit",
    platforms: [
        .iOS("26.0"),
        // Foundation-only tests run on the macOS CI host (Date.now: macOS 12).
        // App and Widget entry points remain iOS-only.
        .macOS(.v12),
    ],
    products: [
        .library(name: "JibunKitCore", targets: ["JibunKitCore"]),
        .library(name: "CounterFeature", targets: ["CounterFeature"]),
        .library(name: "ReminderFeature", targets: ["ReminderFeature"]),
        .library(
            name: "JibunKit",
            targets: ["JibunKit"]
        ),
        .library(
            name: "JibunKitWidget",
            targets: ["JibunKitWidget"]
        ),
    ],
    targets: [
        // jibunkit:feature-targets
        .target(
            name: "JibunKitCore"
        ),
        .target(
            name: "CounterFeature",
            dependencies: ["JibunKitCore"]
        ),
        .target(
            name: "ReminderFeature",
            dependencies: ["JibunKitCore"]
        ),
        .target(
            name: "JibunKit",
            dependencies: [
                "JibunKitCore",
                "CounterFeature",
                "ReminderFeature",
                // jibunkit:feature-dependencies
            ]
        ),
        .target(
            name: "JibunKitWidget",
            dependencies: ["CounterFeature"]
        ),
        .testTarget(
            name: "CounterFeatureTests",
            dependencies: ["CounterFeature"]
        ),
        .testTarget(
            name: "JibunKitCoreTests",
            dependencies: ["JibunKitCore"]
        ),
        .testTarget(
            name: "MiniAppIntegrationTests",
            dependencies: ["JibunKitCore", "CounterFeature", "ReminderFeature"]
        ),
    ]
)
