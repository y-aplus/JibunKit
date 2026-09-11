import SwiftUI
import WidgetFeatureA
import WidgetFeatureB
import WidgetKit

@main
struct CombinedWidgetBundle: WidgetBundle {
    var body: some Widget {
        FeatureAWidget()
        FeatureBWidget()
    }
}
