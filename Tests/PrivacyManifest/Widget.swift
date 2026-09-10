import Foundation
import PrivacyFeatureB
import SwiftUI
import WidgetKit

@main struct PrivacyHostWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PrivacyFeatureB.owner, provider: Provider()) { _ in Text(PrivacyFeatureB.owner) }
            .configurationDisplayName("Privacy fixture").description("Privacy fixture")
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
