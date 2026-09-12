// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VendorA",
    platforms: [.macOS(.v12)],
    products: [.library(name: "VendorSDK", targets: ["VendorSDK"])],
    targets: [.target(name: "VendorSDK")]
)
