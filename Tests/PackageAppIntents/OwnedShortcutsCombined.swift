import AppIntents
import IntentFeatureAShortcuts
import IntentFeatureBShortcuts
struct HostIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureAShortcutsPackage.self, FeatureBShortcutsPackage.self]
    }
}
