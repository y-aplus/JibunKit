// swift-tools-version: 6.0
import PackageDescription

let package = Package(name: "ContinuingAlarmFeatureA", platforms: [.iOS("26.0")],
    products: [.library(name: "ContinuingAlarmFeatureA", targets: ["ContinuingAlarmFeatureA"])],
    dependencies: [
        .package(name: "ContinuingAlarmSupport", path: "../Support"),
        .package(name: "JibunKit", path: "__JIBUNKIT_PATH__"),
    ],
    targets: [.target(name: "ContinuingAlarmFeatureA", dependencies: [
        .product(name: "ContinuingAlarmSupport", package: "ContinuingAlarmSupport"),
        .product(name: "JibunKitCore", package: "JibunKit"),
    ])])
