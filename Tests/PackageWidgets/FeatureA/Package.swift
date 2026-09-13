// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WidgetFeatureA",
    defaultLocalization: "en",
    platforms: [.iOS("26.0")],
    products: [.library(name: "WidgetFeatureA", targets: ["WidgetFeatureA"])],
    dependencies: [.package(path: "__JIBUNKIT_PATH__")],
    targets: [
        .target(
            name: "WidgetFeatureA",
            dependencies: [.product(name: "JibunKitCore", package: "JibunKit")],
            resources: [.process("Resources")]
        ),
    ]
)
