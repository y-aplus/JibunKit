// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatureB",
    platforms: [.macOS(.v12)],
    products: [.library(name: "FeatureB", targets: ["FeatureB"])],
    dependencies: [.package(path: "../VendorB")],
    targets: [
        .target(
            name: "FeatureB",
            dependencies: [.product(name: "VendorSDK", package: "VendorB")]
        )
    ]
)
