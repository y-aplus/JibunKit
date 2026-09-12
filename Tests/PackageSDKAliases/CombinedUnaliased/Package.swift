// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CombinedUnaliased",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(path: "../FeatureA"),
        .package(path: "../FeatureB"),
    ],
    targets: [
        .testTarget(
            name: "CombinedUnaliasedTests",
            dependencies: [
                .product(name: "FeatureA", package: "FeatureA"),
                .product(name: "FeatureB", package: "FeatureB"),
            ]
        )
    ]
)
