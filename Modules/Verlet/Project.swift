import ProjectDescription

let project = Project(
    name: "VerletExample",
    packages: [.package(path: ".")],
    settings: .settings(base: ["SWIFT_VERSION": "6.0"]),
    targets: [
        .target(
            name: "VerletExample", destinations: .iOS, product: .app,
            bundleId: "com.jibunkit.example.verlet",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
            sources: ["Example/**"],
            dependencies: [.package(product: "VerletFeature")]
        ),
        .target(
            name: "VerletExampleUITests", destinations: .iOS, product: .uiTests,
            bundleId: "com.jibunkit.example.verlet.uitests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default, sources: ["UITests/**"],
            dependencies: [.target(name: "VerletExample")]
        ),
    ],
    schemes: [
        .scheme(name: "VerletExample", shared: true,
                buildAction: .buildAction(targets: ["VerletExample"]),
                testAction: .targets(["VerletExampleUITests"], configuration: .debug)),
    ]
)
