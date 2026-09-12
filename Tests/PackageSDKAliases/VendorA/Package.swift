// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VendorA",
    platforms: [.iOS("26.0"), .macOS(.v12)],
    products: [.library(name: "VendorSDK", targets: ["VendorSDK"])],
    targets: [.target(name: "VendorSDK")]
)
