import AppIntents
import SwiftUI
import WidgetKit
import InteractiveFeatureB
struct FixtureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FeatureBIntents.self] }
}
@main
struct FixtureWidgets: WidgetBundle {
    var body: some Widget {
        FeatureBWidget()
        FeatureBControl()
    }
}
