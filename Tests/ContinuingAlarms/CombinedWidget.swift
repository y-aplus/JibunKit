import ContinuingAlarmFeatureA
import ContinuingAlarmFeatureB
import SwiftUI
import WidgetKit

@main struct AlarmCombinedWidgets: WidgetBundle {
    var body: some Widget { FeatureAAlarmLiveActivity(); FeatureBAlarmLiveActivity() }
}
