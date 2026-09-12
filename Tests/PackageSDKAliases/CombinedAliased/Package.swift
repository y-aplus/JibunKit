// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CombinedAliased",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(path: "../FeatureA"),
        .package(path: "../FeatureB"),
    ],
    targets: [
        .testTarget(
            name: "CombinedAliasedTests",
            dependencies: [
                .product(
                    name: "FeatureA",
                    package: "FeatureA",
                    moduleAliases: ["VendorSDK": "VendorASDK"]
                ),
                .product(
                    name: "FeatureB",
                    package: "FeatureB",
                    moduleAliases: ["VendorSDK": "VendorBSDK"]
                ),
            ]
        )
    ]
)
