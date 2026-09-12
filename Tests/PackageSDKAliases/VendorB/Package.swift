// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VendorB",
    platforms: [.macOS(.v12)],
    products: [.library(name: "VendorSDK", targets: ["VendorSDK"])],
    targets: [.target(name: "VendorSDK")]
)
