// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WidgetFeatureB",
    platforms: [.iOS(.v17)],
    products: [.library(name: "WidgetFeatureB", targets: ["WidgetFeatureB"])],
    dependencies: [.package(path: "__JIBUNKIT_PATH__")],
    targets: [
        .target(
            name: "WidgetFeatureB",
            dependencies: [.product(name: "JibunKitCore", package: "JibunKit")]
        ),
    ]
)
