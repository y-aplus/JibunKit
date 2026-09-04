// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JibunKit",
    platforms: [
        .iOS("26.0"),
    ],
    products: [
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
            dependencies: ["CounterFeature", "ReminderFeature"]
        ),
    ]
)
