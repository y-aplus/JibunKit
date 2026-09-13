import Foundation
import JibunKitCore
import SwiftUI
import WidgetKit

public enum FeatureBStoreError: Error, Equatable, Sendable { case sharedStoreUnavailable }

public final class FeatureBStore: @unchecked Sendable {
    public static let id = MiniAppID("owner-b")
    public static let localKey = "shared-value"
    private let defaults: UserDefaults?
    private let context = MiniAppContext(id: id)

    public convenience init() { self.init(optionalDefaults: try? MiniAppStorage.sharedDefaults()) }
    public init(defaults: UserDefaults) { self.defaults = defaults }
    private init(optionalDefaults: UserDefaults?) { defaults = optionalDefaults }
    public var storageKey: String { context.storageKey(Self.localKey) }

    public func value() throws -> Int? {
        let defaults = try configuredDefaults()
        return MiniAppStorage.withExclusiveAccess {
            guard defaults.object(forKey: storageKey) != nil else { return nil }
            return defaults.integer(forKey: storageKey)
        }
    }
    public func set(_ value: Int) throws {
        let defaults = try configuredDefaults()
        MiniAppStorage.withExclusiveAccess { defaults.set(value, forKey: storageKey) }
    }
    public func seedIfMissing(_ value: Int) throws {
        let defaults = try configuredDefaults()
        MiniAppStorage.withExclusiveAccess {
            guard defaults.object(forKey: storageKey) == nil else { return }
            defaults.set(value, forKey: storageKey)
        }
    }
    public func remove() throws {
        let defaults = try configuredDefaults()
        MiniAppStorage.withExclusiveAccess { defaults.removeObject(forKey: storageKey) }
    }
    public func savedStatus() throws -> MiniAppManagement.Status {
        MiniAppManagement.savedStatus(for: Self.id, defaults: try configuredDefaults())
    }
    private func configuredDefaults() throws -> UserDefaults {
        guard let defaults else { throw FeatureBStoreError.sharedStoreUnavailable }
        return defaults
    }
}

public struct FeatureBAccess: Sendable {
    private let store: FeatureBStore
    private let coordinator: MiniAppRestoreCoordinator
    public init(store: FeatureBStore, coordinator: MiniAppRestoreCoordinator = .shared) {
        self.store = store
        self.coordinator = coordinator
    }
    public func value() async throws -> Int? {
        try await coordinator.withStoreAccess(for: FeatureBStore.id) { try store.value() }
    }
    public func set(_ value: Int) async throws {
        try await coordinator.withStoreAccess(for: FeatureBStore.id) { try store.set(value) }
    }
    public func increment() async throws -> Int {
        try await coordinator.withStoreAccess(for: FeatureBStore.id) {
            let updated = (try store.value() ?? 0) + 1
            try store.set(updated)
            return updated
        }
    }
}

#if os(iOS)
@MainActor
public enum FeatureBMiniApp {
    public static let lifetime = MiniAppFeatureLifetime(id: FeatureBStore.id)
    public static func definition(
        store: FeatureBStore,
        lifetime: MiniAppFeatureLifetime = FeatureBMiniApp.lifetime,
        coordinator: MiniAppRestoreCoordinator = .shared
    ) -> MiniAppDefinition {
        MiniAppDefinition(
            id: FeatureBStore.id, title: text("miniapp.title"), systemImage: "b.square",
            lifetime: lifetime,
            removal: MiniAppRemovalProvider(
                id: FeatureBStore.id, dataDescription: text("miniapp.data-description"),
                removeData: { try store.remove() }
            )
        ) { _ in FeatureBRootView(access: FeatureBAccess(store: store, coordinator: coordinator)) }
    }
}

private struct FeatureBRootView: View {
    let access: FeatureBAccess
    @State private var value: Int?
    @State private var message = "loading"
    var body: some View {
        VStack(spacing: 12) {
            Text(value.map(String.init) ?? "--").accessibilityIdentifier("widget-feature-b.value")
            Button(text("miniapp.increment")) { update() }
                .accessibilityIdentifier("widget-feature-b.increment")
            Text(message).accessibilityIdentifier("widget-feature-b.status")
        }
        .task { await load() }
    }
    private func load() async {
        do {
            value = try await access.value()
            message = "ready"
        } catch { message = "error:\(error)" }
    }
    private func update() {
        Task {
            do {
                value = try await access.increment()
                WidgetCenter.shared.reloadTimelines(ofKind: FeatureBWidget.kind)
                message = "updated"
            } catch { message = "error:\(error)" }
        }
    }
}
#endif

public struct FeatureBEntry: TimelineEntry, Sendable {
    public let date: Date
    public let owner: String
    public let storageKey: String
    public let value: Int?
    public let status: MiniAppManagement.Status?
    public let storeAvailable: Bool
}

public struct FeatureBProvider: TimelineProvider, @unchecked Sendable {
    private let store: FeatureBStore
    public init(store: FeatureBStore = FeatureBStore()) { self.store = store }
    public func timeline(date: Date = .now) -> Timeline<FeatureBEntry> {
        let entry: FeatureBEntry
        do {
            let status = try store.savedStatus()
            entry = FeatureBEntry(
                date: date, owner: FeatureBStore.id.rawValue, storageKey: store.storageKey,
                value: status == .enabled ? try store.value() : nil,
                status: status, storeAvailable: true
            )
        } catch {
            entry = FeatureBEntry(date: date, owner: FeatureBStore.id.rawValue, storageKey: store.storageKey,
                                  value: nil, status: nil, storeAvailable: false)
        }
        return Timeline(entries: [entry], policy: .never)
    }
    public func placeholder(in context: Context) -> FeatureBEntry {
        FeatureBEntry(date: .now, owner: FeatureBStore.id.rawValue, storageKey: store.storageKey,
                      value: 0, status: .enabled, storeAvailable: true)
    }
    public func getSnapshot(in context: Context, completion: @escaping @Sendable (FeatureBEntry) -> Void) {
        completion(timeline().entries[0])
    }
    public func getTimeline(in context: Context,
                            completion: @escaping @Sendable (Timeline<FeatureBEntry>) -> Void) {
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
            Text(!entry.storeAvailable ? "B:unavailable" : entry.status != .enabled ? "B:--" : entry.value.map { "B:\($0)" } ?? "B:empty")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Self.displayName)
        .description(Self.widgetDescription)
    }
}

private func text(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: key, table: nil)
}
