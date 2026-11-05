import ProjectDescription

let project = Project(
    name: "LocationCheckExample",
    packages: [.package(path: ".")],
    settings: .settings(base: ["SWIFT_VERSION": "6.0"]),
    targets: [
        .target(
            name: "LocationCheckExample", destinations: .iOS, product: .app,
            bundleId: "com.jibunkit.example.locationcheck",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
            sources: ["Example/**"],
            dependencies: [.package(product: "LocationCheckFeature")]
        ),
        .target(
            name: "LocationCheckExampleUITests", destinations: .iOS, product: .uiTests,
            bundleId: "com.jibunkit.example.locationcheck.uitests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default, sources: ["UITests/**"],
            dependencies: [.target(name: "LocationCheckExample")]
        ),
    ],
    schemes: [
        .scheme(name: "LocationCheckExample", shared: true,
                buildAction: .buildAction(targets: ["LocationCheckExample"]),
                testAction: .targets(["LocationCheckExampleUITests"], configuration: .debug)),
    ]
)
