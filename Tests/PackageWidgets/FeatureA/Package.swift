// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WidgetFeatureA",
    platforms: [.iOS(.v17)],
    products: [.library(name: "WidgetFeatureA", targets: ["WidgetFeatureA"])],
    targets: [.target(name: "WidgetFeatureA")]
)
