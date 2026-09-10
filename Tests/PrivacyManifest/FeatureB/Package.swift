// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrivacyFeatureB",
    platforms: [.iOS("26.0"), .macOS(.v12)],
    products: [.library(name: "PrivacyFeatureB", targets: ["PrivacyFeatureB"])],
    targets: [.target(name: "PrivacyFeatureB", resources: [.process("PrivacyInfo.xcprivacy")])]
)
