// swift-tools-version: 6.0
import PackageDescription

let package = Package(name: "ContinuingAlarmFeatureB", platforms: [.iOS("26.0")],
    products: [.library(name: "ContinuingAlarmFeatureB", targets: ["ContinuingAlarmFeatureB"])],
    dependencies: [
        .package(name: "ContinuingAlarmSupport", path: "../Support"),
        .package(name: "JibunKit", path: "__JIBUNKIT_PATH__"),
    ],
    targets: [.target(name: "ContinuingAlarmFeatureB", dependencies: [
        .product(name: "ContinuingAlarmSupport", package: "ContinuingAlarmSupport"),
        .product(name: "JibunKitCore", package: "JibunKit"),
    ])])
