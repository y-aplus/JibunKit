// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ResourceFeatureA",
    defaultLocalization: "en",
    platforms: [.iOS("26.0")],
    products: [.library(name: "ResourceFeatureA", targets: ["ResourceFeatureA"])],
    targets: [.target(name: "ResourceFeatureA", resources: [.process("Resources")])]
)
