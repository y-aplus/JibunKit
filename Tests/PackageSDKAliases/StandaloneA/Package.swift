// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StandaloneA",
    platforms: [.macOS(.v12)],
    dependencies: [.package(path: "../FeatureA")],
    targets: [
        .testTarget(
            name: "StandaloneATests",
            dependencies: [.product(name: "FeatureA", package: "FeatureA")]
        )
    ]
)
