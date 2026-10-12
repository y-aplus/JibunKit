// swift-tools-version: 6.0
// Written by `jibunkit-feature.py migrate`.
import PackageDescription

let package = Package(
    name: "Zap",
    defaultLocalization: "en",
    platforms: [.iOS("26.0")],
    products: [.library(name: "ZapFeature", targets: ["ZapFeature"])],
    targets: [
        .target(
            name: "ZapFeature",
            resources: [
                .process("Assets.xcassets"),
                .process("Localizable.xcstrings"),
                .process("Preview Content/Preview Assets.xcassets"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
