// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StandaloneA",
    dependencies: [.package(path: "../FeatureA")],
    targets: [
        .testTarget(
            name: "StandaloneATests",
            dependencies: [.product(name: "FeatureA", package: "FeatureA")]
        )
    ]
)
