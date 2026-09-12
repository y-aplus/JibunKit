// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StandaloneB",
    platforms: [.macOS(.v12)],
    dependencies: [.package(path: "../FeatureB")],
    targets: [
        .testTarget(
            name: "StandaloneBTests",
            dependencies: [.product(name: "FeatureB", package: "FeatureB")]
        )
    ]
)
