// swift-tools-version: 6.0
// Written by `jibunkit-feature.py migrate`.
import PackageDescription

let package = Package(
    name: "Verlet",
    platforms: [.iOS("26.0")],
    products: [.library(name: "VerletFeature", targets: ["VerletFeature"])],
    dependencies: [
        .package(url: "https://github.com/MetalBuilder/MetalBuilder", "0.2.3"..<"1.0.0"),
        .package(url: "https://github.com/gadirom/TransformGesture", "0.0.1"..<"1.0.0"),
    ],
    targets: [
        .target(
            name: "VerletFeature",
            dependencies: [
                .product(name: "MetalBuilder", package: "metalbuilder"),
                .product(name: "TransformGesture", package: "transformgesture"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
