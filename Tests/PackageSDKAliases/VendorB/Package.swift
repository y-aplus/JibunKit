// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VendorB",
    products: [.library(name: "VendorSDK", targets: ["VendorSDK"])],
    targets: [.target(name: "VendorSDK")]
)
