import Foundation
import SwiftUI
import WidgetKit

@main
struct BuildRequirementProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BuildRequirementProbeWidget", provider: Provider()) { _ in
            Text("Probe")
        }
        .configurationDisplayName("Probe")
        .description("Probe")
    }
}

private struct Entry: TimelineEntry { let date = Date() }
private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry() }
    func getSnapshot(in context: Context, completion: @escaping @Sendable (Entry) -> Void) { completion(Entry()) }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry()], policy: .never))
    }
}
