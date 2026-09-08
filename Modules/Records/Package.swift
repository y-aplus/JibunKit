// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Records",
    platforms: [.iOS("26.0"), .macOS(.v12)],
    products: [.library(name: "RecordsFeature", targets: ["RecordsFeature"])],
    targets: [.target(name: "RecordsFeature"),
              .testTarget(name: "RecordsFeatureTests", dependencies: ["RecordsFeature"])]
)
