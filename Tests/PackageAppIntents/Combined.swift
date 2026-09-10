import AppIntents
import IntentFeatureA
import IntentFeatureB
struct HostIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureAIntentPackage.self, FeatureBIntentPackage.self]
    }
}
struct HostShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FeatureAAddValueIntent(), phrases: ["Add A in \(.applicationName)"],
                    shortTitle: "Add A", systemImageName: "plus.circle")
        AppShortcut(intent: FeatureBAddValueIntent(), phrases: ["Add B in \(.applicationName)"],
                    shortTitle: "Add B", systemImageName: "plus.square")
    }
}
