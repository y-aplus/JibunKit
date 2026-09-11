// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WidgetFeatureB",
    platforms: [.iOS(.v17)],
    products: [.library(name: "WidgetFeatureB", targets: ["WidgetFeatureB"])],
    targets: [.target(name: "WidgetFeatureB")]
)
