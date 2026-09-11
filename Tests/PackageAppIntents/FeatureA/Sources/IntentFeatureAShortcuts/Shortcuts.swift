import AppIntents
import IntentFeatureA

public struct FeatureAShortcutsPackage: AppIntentsPackage {
    public static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureAIntentPackage.self]
    }
}

public struct FeatureAShortcuts: AppShortcutsProvider {
    public static var addValue: AppShortcut {
        AppShortcut(intent: FeatureAAddValueIntent(),
                    phrases: ["Add A in \(.applicationName)"],
                    shortTitle: "Add A", systemImageName: "plus.circle")
    }

    public static var appShortcuts: [AppShortcut] {
        addValue
    }
}
