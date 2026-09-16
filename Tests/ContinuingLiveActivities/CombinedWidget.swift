import AppIntents
import ContinuingFeatureA
import ContinuingFeatureB
import SwiftUI
import WidgetKit
struct FixtureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAIntents.self, FeatureBIntents.self] }
}
@main struct FixtureWidgets: WidgetBundle {
    var body: some Widget { FeatureALiveActivityWidget(); FeatureBLiveActivityWidget() }
}
