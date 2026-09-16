// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ContinuingFeatureB", platforms: [.iOS("26.0")],
    products: [.library(name: "ContinuingFeatureB", targets: ["ContinuingFeatureB"])],
    dependencies: [.package(path: "__JIBUNKIT_PATH__")],
    targets: [.target(name: "ContinuingFeatureB",
        dependencies: [.product(name: "JibunKitCore", package: "JibunKit")])])
