// swift-tools-version: 6.0
import PackageDescription

let package = Package(name: "ContinuingAlarmSupport", platforms: [.iOS("26.0")],
    products: [.library(name: "ContinuingAlarmSupport", targets: ["ContinuingAlarmSupport"])],
    dependencies: [.package(name: "JibunKit", path: "__JIBUNKIT_PATH__")],
    targets: [.target(name: "ContinuingAlarmSupport",
        dependencies: [.product(name: "JibunKitCore", package: "JibunKit")])])
