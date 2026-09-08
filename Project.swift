import ProjectDescription

let project = Project(
    name: "JibunKit",
    packages: [.package(path: ".")],
    settings: .settings(base: ["SWIFT_VERSION": "6.0"]),
    targets: [
        .target(
            name: "JibunKit-App", destinations: .iOS, product: .app,
            bundleId: "com.jibunkit.app", deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "JibunKit", "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "2", "JibunKitAppGroup": "group.com.jibunkit.shared",
                "UILaunchScreen": [:],
                "CFBundleURLTypes": [[
                    "CFBundleURLName": "com.jibunkit.app.mini-app",
                    "CFBundleURLSchemes": ["jibunkit"],
                ]],
            ]),
            sources: ["Sources/JibunKit/**"],
            entitlements: "JibunKit.entitlements",
            dependencies: [.package(product: "JibunKitCore"), .package(product: "CounterFeature"),
                           .package(product: "ReminderFeature"), .package(product: "CounterIntegration"),
                           .package(product: "ReminderIntegration"), .target(name: "JibunKitWidget-Extension")]
        ),
        .target(
            name: "JibunKitWidget-Extension", destinations: .iOS, product: .appExtension,
            bundleId: "com.jibunkit.app.Widget", deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "2",
                "JibunKitAppGroup": "group.com.jibunkit.shared",
                "NSExtension": ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"],
            ]),
            sources: ["Sources/JibunKitWidget/**"],
            entitlements: "JibunKitWidget.entitlements",
            dependencies: [.package(product: "CounterFeature"), .package(product: "JibunKitCore")]
        ),
        .target(
            name: "MigrationUITests", destinations: .iOS, product: .uiTests,
            bundleId: "com.jibunkit.migration-tests", deploymentTargets: .iOS("26.0"),
            infoPlist: .default, sources: ["UITests/**"],
            dependencies: [.target(name: "JibunKit-App")]
        ),
        .target(
            name: "CounterExample", destinations: .iOS, product: .app,
            bundleId: "com.jibunkit.counterexample", deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
            sources: ["Examples/Counter/**"],
            dependencies: [.package(product: "CounterFeature"), .package(product: "JibunKitCore")]
        ),
    ],
    schemes: [
        .scheme(name: "MigrationUITests", shared: true,
                buildAction: .buildAction(targets: ["JibunKit-App"]),
                testAction: .targets(["MigrationUITests"], configuration: .debug)),
    ]
)
