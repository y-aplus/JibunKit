// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppbaseIOS",
    platforms: [
        .iOS("26.0"),
    ],
    products: [
        .library(
            name: "AppbaseIOS",
            targets: ["AppbaseIOS"]
        ),
        .library(
            name: "AppbaseIOSWidget",
            targets: ["AppbaseIOSWidget"]
        ),
    ],
    targets: [
        .target(
            name: "CounterFeature"
        ),
        .target(
            name: "AppbaseIOS",
            dependencies: ["CounterFeature"]
        ),
        .target(
            name: "AppbaseIOSWidget",
            dependencies: ["CounterFeature"]
        ),
        .testTarget(
            name: "CounterFeatureTests",
            dependencies: ["CounterFeature"]
        ),
    ]
)
