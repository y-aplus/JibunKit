// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Builder",
    defaultLocalization: "en",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [.library(name: "BuilderFeature", targets: ["BuilderFeature"])],
    targets: [
        .target(name: "BuilderFeature", resources: [.process("Resources")]),
        .testTarget(name: "BuilderFeatureTests", dependencies: ["BuilderFeature"]),
    ]
)
