// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FeatureA",
    products: [.library(name: "FeatureA", targets: ["FeatureA"])],
    dependencies: [.package(path: "../VendorA")],
    targets: [
        .target(
            name: "FeatureA",
            dependencies: [.product(name: "VendorSDK", package: "VendorA")]
        )
    ]
)
