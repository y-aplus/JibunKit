import SwiftUI
import WidgetKit

public struct FeatureBEntry: TimelineEntry, Sendable {
    public let date: Date
    public let owner: String
    public let storageKey: String

    public init(date: Date, owner: String = "owner-b", storageKey: String = "owner-b.shared-value") {
        self.date = date
        self.owner = owner
        self.storageKey = storageKey
    }
}

public struct FeatureBProvider: TimelineProvider {
    public init() {}
    public static func fixtureTimeline(date: Date = .now) -> Timeline<FeatureBEntry> {
        Timeline(entries: [FeatureBEntry(date: date)], policy: .never)
    }
    public func placeholder(in context: Context) -> FeatureBEntry { FeatureBEntry(date: .now) }
    public func getSnapshot(in context: Context, completion: @escaping @Sendable (FeatureBEntry) -> Void) {
        completion(FeatureBEntry(date: .now))
    }
    public func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<FeatureBEntry>) -> Void
    ) {
        completion(Self.fixtureTimeline())
    }
}

public struct FeatureBWidget: Widget {
    public static let kind = "com.jibunkit.fixture.feature-b.widget"
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FeatureBProvider()) { entry in
            Text("B:\(entry.storageKey)")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Feature B")
        .description("Static widget owned by Feature B")
    }
}
