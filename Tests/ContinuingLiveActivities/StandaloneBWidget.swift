import AppIntents
import ContinuingFeatureB
import SwiftUI
import WidgetKit
struct FixtureIntents: AppIntentsPackage { static var includedPackages: [any AppIntentsPackage.Type] { [FeatureBIntents.self] } }
@main struct FixtureWidgets: WidgetBundle { var body: some Widget { FeatureBLiveActivityWidget() } }
