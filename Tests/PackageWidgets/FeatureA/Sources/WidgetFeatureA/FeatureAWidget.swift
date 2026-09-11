import SwiftUI
import WidgetKit

public struct FeatureAEntry: TimelineEntry, Sendable {
    public let date: Date
    public let owner: String
    public let storageKey: String

    public init(date: Date, owner: String = "owner-a", storageKey: String = "owner-a.shared-value") {
        self.date = date
        self.owner = owner
        self.storageKey = storageKey
    }
}

public struct FeatureAProvider: TimelineProvider {
    public init() {}
    public static func fixtureTimeline(date: Date = .now) -> Timeline<FeatureAEntry> {
        Timeline(entries: [FeatureAEntry(date: date)], policy: .never)
    }
    public func placeholder(in context: Context) -> FeatureAEntry { FeatureAEntry(date: .now) }
    public func getSnapshot(in context: Context, completion: @escaping @Sendable (FeatureAEntry) -> Void) {
        completion(FeatureAEntry(date: .now))
    }
    public func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<FeatureAEntry>) -> Void
    ) {
        completion(Self.fixtureTimeline())
    }
}

public struct FeatureAWidget: Widget {
    public static let kind = "com.jibunkit.fixture.feature-a.widget"
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FeatureAProvider()) { entry in
            Text("A:\(entry.storageKey)")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Feature A")
        .description("Static widget owned by Feature A")
    }
}
