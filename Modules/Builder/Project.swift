import ProjectDescription

let project = Project(
    name: "BuilderExample",
    packages: [.package(path: ".")],
    settings: .settings(base: ["SWIFT_VERSION": "6.0"]),
    targets: [
        .target(
            name: "BuilderExample", destinations: .iOS, product: .app,
            bundleId: "com.jibunkit.example.builder",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
            sources: ["Example/**"],
            dependencies: [.package(product: "BuilderFeature")]
        ),
        .target(
            name: "BuilderExampleUITests", destinations: .iOS, product: .uiTests,
            bundleId: "com.jibunkit.example.builder.uitests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default, sources: ["UITests/**"],
            dependencies: [.target(name: "BuilderExample")]
        ),
    ],
    schemes: [
        .scheme(name: "BuilderExample", shared: true,
                buildAction: .buildAction(targets: ["BuilderExample"]),
                testAction: .targets(["BuilderExampleUITests"], configuration: .debug)),
    ]
)
