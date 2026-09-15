import AppIntents
import WidgetKit
import InteractiveFeatureA
import InteractiveFeatureB
struct FixtureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAIntents.self, FeatureBIntents.self] }
}
@main
struct FixtureWidgets: WidgetBundle {
    var body: some Widget {
        FeatureAWidget()
        FeatureAControl()
        FeatureBWidget()
        FeatureBControl()
    }
}
