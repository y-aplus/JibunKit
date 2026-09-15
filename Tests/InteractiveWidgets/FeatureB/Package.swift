// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "InteractiveFeatureB", platforms: [.iOS("26.0")],
    products: [.library(name: "InteractiveFeatureB", targets: ["InteractiveFeatureB"])],
    dependencies: [.package(path: "__JIBUNKIT_PATH__")],
    targets: [.target(name: "InteractiveFeatureB", dependencies: [.product(name: "JibunKitCore", package: "JibunKit")])])
