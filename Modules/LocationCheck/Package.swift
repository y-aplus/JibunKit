// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocationCheck",
    platforms: [.iOS("26.0")],
    products: [.library(name: "LocationCheckFeature", targets: ["LocationCheckFeature"])],
    targets: [.target(name: "LocationCheckFeature")]
)
