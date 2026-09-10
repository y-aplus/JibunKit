// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrivacyFeatureA",
    platforms: [.iOS("26.0"), .macOS(.v12)],
    products: [.library(name: "PrivacyFeatureA", targets: ["PrivacyFeatureA"])],
    targets: [.target(name: "PrivacyFeatureA", resources: [.process("PrivacyInfo.xcprivacy")])]
)
