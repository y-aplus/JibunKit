#if canImport(AlarmKit) && canImport(ActivityKit) && canImport(WidgetKit)
import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@available(iOS 26.0, *)
public struct FeatureAAlarmLiveActivity: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<FeatureAAlarmMetadata>.self) { context in
            VStack { Text("Feature A"); Text(context.attributes.metadata.reason) }
                .activityBackgroundTint(.orange.opacity(0.2))
        } dynamicIsland: { _ in
            DynamicIsland { DynamicIslandExpandedRegion(.center) { Text("A 集中") } }
                compactLeading: { Text("A") } compactTrailing: { Image(systemName: "timer") }
                minimal: { Text("A") }
        }
    }
}

@available(iOS 26.0, *)
public struct FeatureBAlarmLiveActivity: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<FeatureBAlarmMetadata>.self) { context in
            VStack { Text("Feature B"); Text(context.attributes.metadata.routine) }
                .activityBackgroundTint(.blue.opacity(0.2))
        } dynamicIsland: { _ in
            DynamicIsland { DynamicIslandExpandedRegion(.center) { Text("B 服薬") } }
                compactLeading: { Text("B") } compactTrailing: { Image(systemName: "pills") }
                minimal: { Text("B") }
        }
    }
}

@main
struct ContinuingAlarmFixtureWidgets: WidgetBundle {
    var body: some Widget {
        #if ALARM_FEATURE_A
        FeatureAAlarmLiveActivity()
        #endif
        #if ALARM_FEATURE_B
        FeatureBAlarmLiveActivity()
        #endif
    }
}
#endif
