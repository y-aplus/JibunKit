// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StandaloneB",
    dependencies: [.package(path: "../FeatureB")],
    targets: [
        .testTarget(
            name: "StandaloneBTests",
            dependencies: [.product(name: "FeatureB", package: "FeatureB")]
        )
    ]
)
