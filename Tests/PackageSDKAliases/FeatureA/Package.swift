// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatureA",
    platforms: [.iOS("26.0"), .macOS(.v12)],
    products: [.library(name: "FeatureA", targets: ["FeatureA"])],
    dependencies: [.package(path: "../VendorA")],
    targets: [
        .target(
            name: "FeatureA",
            dependencies: [.product(name: "VendorSDK", package: "VendorA")]
        )
    ]
)
