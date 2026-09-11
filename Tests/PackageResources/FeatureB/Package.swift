// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ResourceFeatureB",
    defaultLocalization: "en",
    platforms: [.iOS("26.0")],
    products: [.library(name: "ResourceFeatureB", targets: ["ResourceFeatureB"])],
    targets: [.target(name: "ResourceFeatureB", resources: [.process("Resources")])]
)
