import AppIntents
import IntentFeatureB

public struct FeatureBShortcutsPackage: AppIntentsPackage {
    public static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureBIntentPackage.self]
    }
}

public struct FeatureBShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FeatureBAddValueIntent(),
                    phrases: ["Add B in \(.applicationName)"],
                    shortTitle: "Add B", systemImageName: "plus.square")
    }
}
