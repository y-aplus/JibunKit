import AppIntents
import IntentFeatureB
import SwiftUI
struct HostIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureBIntentPackage.self]
    }
}
@MainActor enum IntentFixtureBootstrap { static func start() {} }
struct IntentFixtureRootView: View { var body: some View { Text("Package App Shortcuts fixture B") } }
