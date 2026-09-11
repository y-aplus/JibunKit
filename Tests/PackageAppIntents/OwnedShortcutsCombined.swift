import AppIntents
import IntentFeatureAShortcuts
import IntentFeatureBShortcuts
struct HostIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureAShortcutsPackage.self, FeatureBShortcutsPackage.self]
    }
}

// No intent, phrase, title, or symbol is copied into the host.
struct HostShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return FeatureAShortcuts.appShortcuts + FeatureBShortcuts.appShortcuts
    }
}
