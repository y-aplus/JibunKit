import AppIntents
import IntentFeatureBShortcuts
struct HostIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureBShortcutsPackage.self]
    }
}

// Keep phrases and AppShortcut construction in the Feature-owned module.
struct HostShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return FeatureBShortcuts.appShortcuts
    }
}
