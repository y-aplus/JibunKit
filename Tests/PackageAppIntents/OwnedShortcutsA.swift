import AppIntents
import IntentFeatureAShortcuts
struct HostIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureAShortcutsPackage.self]
    }
}
