// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "IntentFeatureA", platforms: [.iOS("26.0")],
    products: [
        .library(name: "IntentFeatureA", targets: ["IntentFeatureA"]),
        .library(name: "IntentFeatureAShortcuts", targets: ["IntentFeatureAShortcuts"]),
    ],
    targets: [
        .target(name: "IntentFeatureA"),
        .target(name: "IntentFeatureAShortcuts", dependencies: ["IntentFeatureA"]),
    ])
