import AppIntents
import ContinuingFeatureB
import SwiftUI
struct FixtureIntents: AppIntentsPackage { static var includedPackages: [any AppIntentsPackage.Type] { [FeatureBIntents.self] } }
@main struct FixtureHost: App { var body: some Scene { WindowGroup { FeatureBDiagnosticView() } } }
