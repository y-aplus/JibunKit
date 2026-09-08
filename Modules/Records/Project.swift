import ProjectDescription

let project = Project(
    name: "RecordsExample",
    packages: [.package(path: ".")],
    settings: .settings(base: ["SWIFT_VERSION": "6.0"]),
    targets: [
        .target(
            name: "RecordsExample", destinations: .iOS, product: .app,
            bundleId: "com.jibunkit.example.records",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: ["UILaunchScreen": [:], "UIFileSharingEnabled": true,
                                               "LSSupportsOpeningDocumentsInPlace": true]),
            sources: ["Example/**"],
            dependencies: [.package(product: "RecordsFeature")]
        ),
        .target(
            name: "RecordsExampleUITests", destinations: .iOS, product: .uiTests,
            bundleId: "com.jibunkit.example.records.uitests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default, sources: ["UITests/**"],
            dependencies: [.target(name: "RecordsExample")]
        ),
    ],
    schemes: [
        .scheme(name: "RecordsExample", shared: true,
                buildAction: .buildAction(targets: ["RecordsExample"]),
                testAction: .targets(["RecordsExampleUITests"], configuration: .debug)),
    ]
)
