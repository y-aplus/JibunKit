import AppIntents
import IntentFeatureBShortcuts
struct HostIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureBShortcutsPackage.self]
    }
}
