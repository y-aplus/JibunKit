// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "IntentFeatureB", platforms: [.iOS("26.0")],
    products: [
        .library(name: "IntentFeatureB", targets: ["IntentFeatureB"]),
        .library(name: "IntentFeatureBShortcuts", targets: ["IntentFeatureBShortcuts"]),
    ],
    targets: [
        .target(name: "IntentFeatureB"),
        .target(name: "IntentFeatureBShortcuts", dependencies: ["IntentFeatureB"]),
    ])
