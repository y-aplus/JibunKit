// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ContinuingFeatureA", platforms: [.iOS("26.0")],
    products: [.library(name: "ContinuingFeatureA", targets: ["ContinuingFeatureA"])],
    dependencies: [.package(path: "__JIBUNKIT_PATH__")],
    targets: [.target(name: "ContinuingFeatureA",
        dependencies: [.product(name: "JibunKitCore", package: "JibunKit")])])
