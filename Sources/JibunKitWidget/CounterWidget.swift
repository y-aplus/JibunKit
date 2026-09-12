#if os(iOS)
import CounterFeature
import JibunKitCore
import SwiftUI
import WidgetKit

@main
struct JibunKitWidgetBundle: WidgetBundle {
    var body: some Widget {
        CounterWidget()
    }
}

struct CounterWidget: Widget {
    static let kind = "JibunKitCounterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CounterProvider()) { entry in
            VStack(spacing: 4) {
                Text("カウンター")
                    .font(.caption)
                if let status = entry.status, status != .enabled {
                    Text(status == .removed ? "削除済み" : status == .disabled ? "無効" : "停止中")
                        .font(.caption)
                } else if let value = entry.value {
                    Text(value, format: .number)
                        .font(.title)
                        .monospacedDigit()
                } else {
                    Text("読取不可")
                        .font(.caption)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(MiniAppLink.url(for: MiniAppID("counter")))
        }
        .configurationDisplayName("カウンター")
        .description("アプリとショートカットが更新した値を表示します。")
    }
}

private struct CounterEntry: TimelineEntry {
    let date: Date
    let value: Int?
    var status: MiniAppManagement.Status? = nil
}

private struct CounterProvider: TimelineProvider {
    func placeholder(in context: Context) -> CounterEntry {
        CounterEntry(date: .now, value: 0)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (CounterEntry) -> Void
    ) {
        Task {
            completion(await entry())
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<CounterEntry>) -> Void
    ) {
        Task {
            let currentEntry = await entry()
            completion(Timeline(
                entries: [currentEntry],
                policy: .after(.now.addingTimeInterval(15 * 60))
            ))
        }
    }

    private func entry() async -> CounterEntry {
        guard let defaults = try? MiniAppStorage.sharedDefaults() else {
            return CounterEntry(date: .now, value: nil)
        }
        let status = MiniAppManagement.savedStatus(for: .counter, defaults: defaults)
        guard status == .enabled else { return CounterEntry(date: .now, value: nil, status: status) }
        let value = try? await CounterStore.shared.currentValue()
        return CounterEntry(date: .now, value: value, status: status)
    }
}
#endif
