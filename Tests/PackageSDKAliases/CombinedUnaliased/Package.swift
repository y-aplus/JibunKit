// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CombinedUnaliased",
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
