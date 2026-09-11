import AppIntents
import IntentFeatureAShortcuts
struct HostIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureAShortcutsPackage.self]
    }
}

// Keep phrases and AppShortcut construction in the Feature-owned module.
struct HostShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        FeatureAShortcuts.addValue
    }
}
