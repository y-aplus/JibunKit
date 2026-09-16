import AppIntents
import ContinuingFeatureA
import SwiftUI
import WidgetKit
struct FixtureIntents: AppIntentsPackage { static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAIntents.self] } }
@main struct FixtureWidgets: WidgetBundle { var body: some Widget { FeatureALiveActivityWidget() } }
