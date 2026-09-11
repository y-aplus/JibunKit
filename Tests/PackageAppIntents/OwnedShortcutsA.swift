import AppIntents
import IntentFeatureA
struct HostIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureAIntentPackage.self]
    }
}
