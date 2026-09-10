// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "IntentFeatureA", platforms: [.iOS("26.0")],
    products: [.library(name: "IntentFeatureA", targets: ["IntentFeatureA"])],
    targets: [.target(name: "IntentFeatureA")])
