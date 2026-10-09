#if os(iOS)
import SwiftUI
import WidgetKit

/// Copied by CI into the generated Notes Feature's Widget directory to prove a
/// module widget reaches the host bundle through JibunKitFeature.json.
struct NotesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.jibunkit.ci.module-notes", provider: NotesWidgetProvider()) { _ in
            Text("Notes")
        }
        .configurationDisplayName("Notes")
    }
}

private struct NotesWidgetEntry: TimelineEntry {
    let date: Date
}

private struct NotesWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotesWidgetEntry {
        NotesWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NotesWidgetEntry) -> Void) {
        completion(NotesWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NotesWidgetEntry>) -> Void) {
        completion(Timeline(entries: [NotesWidgetEntry(date: .now)], policy: .never))
    }
}
#endif
