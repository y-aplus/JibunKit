import SwiftUI
import WidgetKit
import JibunKitCore

public struct FeatureAEntry: TimelineEntry, Sendable {
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

public final class FeatureAStore: @unchecked Sendable {
    public static let id = MiniAppID("owner-a")
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
public enum FeatureAMiniApp {
    public static let lifetime = MiniAppFeatureLifetime(id: FeatureAStore.id)
    public static let definition = MiniAppDefinition(
        id: FeatureAStore.id,
        title: text("miniapp.title"),
        systemImage: "a.square",
        lifetime: lifetime,
        removal: MiniAppRemovalProvider(
            id: FeatureAStore.id,
            dataDescription: text("miniapp.data-description"),
            removeData: { FeatureAStore().remove() }
        )
    ) { _ in
        Text(text("miniapp.title"))
    }
}
#endif

private func text(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: key, table: nil)
}

public struct FeatureAProvider: TimelineProvider, @unchecked Sendable {
    private let store: FeatureAStore
    public init(store: FeatureAStore = FeatureAStore()) { self.store = store }
    public func timeline(date: Date = .now) -> Timeline<FeatureAEntry> {
        let enabled = store.isEnabled()
        return Timeline(entries: [FeatureAEntry(
            date: date, owner: "owner-a", storageKey: store.storageKey,
            value: enabled ? store.value() : 0, isEnabled: enabled
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
    public static var displayName: String { text("widget.name") }
    public static var widgetDescription: String { text("widget.description") }
    public static var supportedLocalizations: [String] { Bundle.module.localizations.sorted() }
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FeatureAProvider()) { entry in
            Text(entry.isEnabled ? "A:\(entry.value)" : "A:--")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Self.displayName)
        .description(Self.widgetDescription)
    }
}
