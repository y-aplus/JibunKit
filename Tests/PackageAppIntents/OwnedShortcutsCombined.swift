import AppIntents
import IntentFeatureA
import IntentFeatureB
struct HostIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureAIntentPackage.self, FeatureBIntentPackage.self]
    }
}
