// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "InteractiveFeatureA", platforms: [.iOS("26.0")],
    products: [.library(name: "InteractiveFeatureA", targets: ["InteractiveFeatureA"])],
    dependencies: [.package(path: "__JIBUNKIT_PATH__")],
    targets: [.target(name: "InteractiveFeatureA", dependencies: [.product(name: "JibunKitCore", package: "JibunKit")])])
