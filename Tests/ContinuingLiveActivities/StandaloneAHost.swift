import AppIntents
import ContinuingFeatureA
import SwiftUI
struct FixtureIntents: AppIntentsPackage { static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAIntents.self] } }
@main struct FixtureHost: App { var body: some Scene { WindowGroup { FeatureADiagnosticView() } } }
