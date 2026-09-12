// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FeatureB",
    products: [.library(name: "FeatureB", targets: ["FeatureB"])],
    dependencies: [.package(path: "../VendorB")],
    targets: [
        .target(
            name: "FeatureB",
            dependencies: [.product(name: "VendorSDK", package: "VendorB")]
        )
    ]
)
