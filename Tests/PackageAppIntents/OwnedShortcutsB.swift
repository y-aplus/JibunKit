import AppIntents
import IntentFeatureB
struct HostIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureBIntentPackage.self]
    }
}
