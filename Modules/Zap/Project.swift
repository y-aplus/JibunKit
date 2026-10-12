import ProjectDescription

let project = Project(
    name: "ZapExample",
    packages: [.package(path: ".")],
    settings: .settings(base: ["SWIFT_VERSION": "6.0"]),
    targets: [
        .target(
            name: "ZapExample", destinations: .iOS, product: .app,
            bundleId: "com.jibunkit.example.zap",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
            sources: ["Example/**"],
            dependencies: [.package(product: "ZapFeature")]
        ),
        .target(
            name: "ZapExampleUITests", destinations: .iOS, product: .uiTests,
            bundleId: "com.jibunkit.example.zap.uitests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default, sources: ["UITests/**"],
            dependencies: [.target(name: "ZapExample")]
        ),
    ],
    schemes: [
        .scheme(name: "ZapExample", shared: true,
                buildAction: .buildAction(targets: ["ZapExample"]),
                testAction: .targets(["ZapExampleUITests"], configuration: .debug)),
    ]
)
