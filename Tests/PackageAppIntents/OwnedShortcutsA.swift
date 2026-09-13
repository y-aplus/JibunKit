import AppIntents
import IntentFeatureA
import SwiftUI
struct HostIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureAIntentPackage.self]
    }
}
@MainActor enum IntentFixtureBootstrap { static func start() {} }
struct IntentFixtureRootView: View { var body: some View { Text("Package App Shortcuts fixture A") } }
