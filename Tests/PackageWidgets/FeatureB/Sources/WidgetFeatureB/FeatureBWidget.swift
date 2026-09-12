import SwiftUI
import WidgetKit
import JibunKitCore

public struct FeatureBEntry: TimelineEntry, Sendable {
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

public final class FeatureBStore: @unchecked Sendable {
    public static let localKey = "shared-value"
    private let defaults: UserDefaults
    private let context = MiniAppContext(id: MiniAppID("owner-b"))

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

public struct FeatureBProvider: TimelineProvider, @unchecked Sendable {
    private let store: FeatureBStore
    public init(store: FeatureBStore = FeatureBStore()) { self.store = store }
    public func timeline(date: Date = .now) -> Timeline<FeatureBEntry> {
        Timeline(entries: [FeatureBEntry(
            date: date, owner: "owner-b", storageKey: store.storageKey, value: store.value()
        )], policy: .never)
    }
    public func placeholder(in context: Context) -> FeatureBEntry { timeline().entries[0] }
    public func getSnapshot(in context: Context, completion: @escaping @Sendable (FeatureBEntry) -> Void) {
        completion(timeline().entries[0])
    }
    public func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<FeatureBEntry>) -> Void
    ) {
        completion(timeline())
    }
}

public struct FeatureBWidget: Widget {
    public static let kind = "com.jibunkit.fixture.feature-b.widget"
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FeatureBProvider()) { entry in
            Text("B:\(entry.value)")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Feature B")
        .description("Static widget owned by Feature B")
    }
}
