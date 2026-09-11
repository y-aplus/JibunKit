import SwiftUI
import WidgetKit
import JibunKitCore

public struct FeatureAEntry: TimelineEntry, Sendable {
    public let date: Date
    public let owner: String
    public let storageKey: String
    public let value: Int

    public init(date: Date, owner: String, storageKey: String, value: Int) {
        self.date = date
        self.owner = owner
        self.storageKey = storageKey
        self.value = value
    }
}

public final class FeatureAStore: @unchecked Sendable {
    public static let localKey = "shared-value"
    private let defaults: UserDefaults
    private let context = MiniAppContext(id: MiniAppID("owner-a"))

    public convenience init() {
        self.init(defaults: (try? MiniAppStorage.sharedDefaults()) ?? .standard)
    }
    public init(defaults: UserDefaults) { self.defaults = defaults }
    public var storageKey: String { context.storageKey(Self.localKey) }
    public func set(_ value: Int) {
        MiniAppStorage.withExclusiveAccess { defaults.set(value, forKey: storageKey) }
    }
    public func value() -> Int {
        MiniAppStorage.withExclusiveAccess { defaults.integer(forKey: storageKey) }
    }
}

public struct FeatureAProvider: TimelineProvider, @unchecked Sendable {
    private let store: FeatureAStore
    public init(store: FeatureAStore = FeatureAStore()) { self.store = store }
    public func timeline(date: Date = .now) -> Timeline<FeatureAEntry> {
        Timeline(entries: [FeatureAEntry(
            date: date, owner: "owner-a", storageKey: store.storageKey, value: store.value()
        )], policy: .never)
    }
    public func placeholder(in context: Context) -> FeatureAEntry { timeline().entries[0] }
    public func getSnapshot(in context: Context, completion: @escaping @Sendable (FeatureAEntry) -> Void) {
        completion(timeline().entries[0])
    }
    public func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<FeatureAEntry>) -> Void
    ) {
        completion(timeline())
    }
}

public struct FeatureAWidget: Widget {
    public static let kind = "com.jibunkit.fixture.feature-a.widget"
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FeatureAProvider()) { entry in
            Text("A:\(entry.value)")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Feature A")
        .description("Static widget owned by Feature A")
    }
}
