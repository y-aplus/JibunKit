// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SDKAliasBridge",
    platforms: [.iOS("26.0")],
    products: [.library(name: "SDKAliasBridge", targets: ["SDKAliasBridge"])],
    dependencies: [
        .package(path: "../FeatureA"),
        .package(path: "../FeatureB"),
    ],
    targets: [
        .target(
            name: "SDKAliasBridge",
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
