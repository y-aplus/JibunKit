// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "IntentFeatureB", platforms: [.iOS("26.0")],
    products: [.library(name: "IntentFeatureB", targets: ["IntentFeatureB"])],
    targets: [.target(name: "IntentFeatureB")])
