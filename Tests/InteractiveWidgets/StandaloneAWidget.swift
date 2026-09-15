import AppIntents
import WidgetKit
import InteractiveFeatureA
struct FixtureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAIntents.self] }
}
@main
struct FixtureWidgets: WidgetBundle {
    var body: some Widget {
        FeatureAWidget()
        FeatureAControl()
    }
}
