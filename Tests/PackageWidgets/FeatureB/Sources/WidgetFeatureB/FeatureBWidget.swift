import SwiftUI
import WidgetKit
import JibunKitCore

public struct FeatureBEntry: TimelineEntry, Sendable {
    public let date: Date
    public let owner: String
    public let storageKey: String
    public let value: Int
    public let isEnabled: Bool

    public init(date: Date, owner: String, storageKey: String, value: Int, isEnabled: Bool = true) {
        self.date = date
        self.owner = owner
        self.storageKey = storageKey
        self.value = value
        self.isEnabled = isEnabled
    }
}

public final class FeatureBStore: @unchecked Sendable {
    public static let id = MiniAppID("owner-b")
    public static let localKey = "shared-value"
    private let defaults: UserDefaults
    private let context = MiniAppContext(id: id)

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
    public func remove() {
        MiniAppStorage.withExclusiveAccess { defaults.removeObject(forKey: storageKey) }
    }
    public func isEnabled() -> Bool {
        MiniAppManagement.savedStatus(for: Self.id, defaults: defaults) == .enabled
    }
}

#if os(iOS)
@MainActor
public enum FeatureBMiniApp {
    public static let lifetime = MiniAppFeatureLifetime(id: FeatureBStore.id)
    public static let definition = MiniAppDefinition(
        id: FeatureBStore.id,
        title: text("miniapp.title"),
        systemImage: "b.square",
        lifetime: lifetime,
        removal: MiniAppRemovalProvider(
            id: FeatureBStore.id,
            dataDescription: text("miniapp.data-description"),
            removeData: { FeatureBStore().remove() }
        )
    ) { _ in
        Text(text("miniapp.title"))
    }
}
#endif

private func text(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: key, table: nil)
}

public struct FeatureBProvider: TimelineProvider, @unchecked Sendable {
    private let store: FeatureBStore
    public init(store: FeatureBStore = FeatureBStore()) { self.store = store }
    public func timeline(date: Date = .now) -> Timeline<FeatureBEntry> {
        let enabled = store.isEnabled()
        return Timeline(entries: [FeatureBEntry(
            date: date, owner: "owner-b", storageKey: store.storageKey,
            value: enabled ? store.value() : 0, isEnabled: enabled
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
    public static var displayName: String { text("widget.name") }
    public static var widgetDescription: String { text("widget.description") }
    public static var supportedLocalizations: [String] { Bundle.module.localizations.sorted() }
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FeatureBProvider()) { entry in
            Text(entry.isEnabled ? "B:\(entry.value)" : "B:--")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Self.displayName)
        .description(Self.widgetDescription)
    }
}
