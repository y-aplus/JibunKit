import AppIntents
import Foundation
import JibunKitCore
import SwiftUI
import WidgetKit

public struct FeatureAState: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public var identity = UUID()
        public var value: Int
    }
    public var items: [String: Item]
    public static var initial: Self { .init(items: ["same-id": .init(value: 10), "second-id": .init(value: 30)]) }
}

public struct FeatureAStore: Sendable {
    public static let owner = MiniAppID("interactive-a")
    public let state: MiniAppSharedState<FeatureAState>
    public init(state: MiniAppSharedState<FeatureAState>) { self.state = state }
    public static func shared() throws -> Self { .init(state: try .shared(owner: owner)) }

    public func entities() throws -> [FeatureAItem] {
        let snapshot = try state.read()
        return snapshot.value.items.sorted { $0.key < $1.key }.map { key, item in
            FeatureAItem(id: "\(snapshot.generation.uuidString)/\(item.identity.uuidString)/\(key)", name: key)
        }
    }

    public func value(for entity: FeatureAItem) throws -> Int {
        let snapshot = try state.read()
        let key = try resolve(entity, in: snapshot)
        guard let item = snapshot.value.items[key] else { throw FeatureAError.missingItem }
        return item.value
    }

    @discardableResult
    public func increment(_ entity: FeatureAItem, failBeforeCommit: Bool = false) throws -> Int {
        let snapshot = try state.read()
        let key = try resolve(entity, in: snapshot)
        return try state.update(generation: snapshot.generation) { value in
            guard var item = value.items[key], item.identity == snapshot.value.items[key]?.identity else {
                throw FeatureAError.missingItem
            }
            let (next, overflow) = item.value.addingReportingOverflow(1)
            guard !overflow else { throw FeatureAError.overflow }
            item.value = next
            value.items[key] = item
            if failBeforeCommit { throw FeatureAError.injected }
            return next
        }
    }

    public func deleteFirstItem() throws {
        let snapshot = try state.read()
        try state.update(generation: snapshot.generation) { $0.items["same-id"] = nil }
    }

    private func resolve(_ entity: FeatureAItem, in snapshot: MiniAppSharedState<FeatureAState>.Snapshot) throws -> String {
        let parts = entity.id.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == snapshot.generation.uuidString,
              let item = snapshot.value.items[parts[2]], parts[1] == item.identity.uuidString else {
            throw FeatureAError.missingItem
        }
        return parts[2]
    }
}

public enum FeatureAError: Error { case missingItem, overflow, injected }

public struct FeatureAItem: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Aの項目")
    public static let defaultQuery = FeatureAQuery()
    public var id: String
    public var name: String
    public var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct FeatureAQuery: EntityQuery {
    public init() {}
    public func entities(for identifiers: [String]) async throws -> [FeatureAItem] {
        let items = try FeatureAStore.shared().entities()
        return identifiers.compactMap { id in items.first { $0.id == id } }
    }
    public func suggestedEntities() async throws -> [FeatureAItem] { try FeatureAStore.shared().entities() }
}

public struct FeatureAWidgetConfiguration: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "操作検証Aの項目"
    @Parameter(title: "項目") public var item: FeatureAItem?
    public init() {}
}

public struct FeatureAControlConfiguration: ControlConfigurationIntent {
    public static let title: LocalizedStringResource = "操作検証AのControl"
    @Parameter(title: "項目") public var item: FeatureAItem?
    public init() {}
}

public struct FeatureAIncrement: AppIntent {
    public static let title: LocalizedStringResource = "操作検証Aを増やす"
    public static let openAppWhenRun = false
    @Parameter(title: "項目") public var item: FeatureAItem
    public init() {}
    public init(item: FeatureAItem) { self.item = item }
    public func perform() async throws -> some IntentResult {
        try Task.checkCancellation()
        try FeatureAStore.shared().increment(item)
        WidgetCenter.shared.reloadTimelines(ofKind: FeatureAWidget.kind)
        ControlCenter.shared.reloadControls(ofKind: FeatureAControl.kind)
        return .result()
    }
}

public struct FeatureAIntents: AppIntentsPackage {}

public struct FeatureAEntry: TimelineEntry, Sendable {
    public let date: Date
    public let item: FeatureAItem?
    public let value: Int?
    public static func current(item: FeatureAItem?, store: FeatureAStore) -> Self {
        guard let item, let value = try? store.value(for: item) else {
            return .init(date: .now, item: nil, value: nil)
        }
        return .init(date: .now, item: item, value: value)
    }
}

public struct FeatureAProvider: AppIntentTimelineProvider {
    public init() {}
    public func placeholder(in context: Context) -> FeatureAEntry { .init(date: .now, item: nil, value: nil) }
    public func snapshot(for configuration: FeatureAWidgetConfiguration, in context: Context) async -> FeatureAEntry {
        current(configuration)
    }
    public func timeline(for configuration: FeatureAWidgetConfiguration, in context: Context) async -> Timeline<FeatureAEntry> {
        .init(entries: [current(configuration)], policy: .after(.now.addingTimeInterval(900)))
    }
    private func current(_ configuration: FeatureAWidgetConfiguration) -> FeatureAEntry {
        guard let store = try? FeatureAStore.shared() else { return .init(date: .now, item: nil, value: nil) }
        return .current(item: configuration.item, store: store)
    }
}

public struct FeatureAWidget: Widget {
    public nonisolated static let kind = "com.jibunkit.fixture.interactive-a.widget"
    public init() {}
    public var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: FeatureAWidgetConfiguration.self, provider: FeatureAProvider()) { entry in
            VStack {
                Text("操作検証 A")
                if let item = entry.item, let value = entry.value {
                    Text("\(item.name): \(value)")
                    Button(intent: FeatureAIncrement(item: item)) { Label("+1", systemImage: "plus") }
                } else { Text("項目を選択／アプリの状態を確認") }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("操作検証 A")
        .description("選択したAの項目だけを更新します")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

public struct FeatureAControlProvider: AppIntentControlValueProvider {
    public init() {}
    public func previewValue(configuration: FeatureAControlConfiguration) -> FeatureAEntry {
        .init(date: .now, item: configuration.item, value: 0)
    }
    public func currentValue(configuration: FeatureAControlConfiguration) async throws -> FeatureAEntry {
        .current(item: configuration.item, store: try FeatureAStore.shared())
    }
}

public struct FeatureAControl: ControlWidget {
    public nonisolated static let kind = "com.jibunkit.fixture.interactive-a.control"
    public init() {}
    public var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: FeatureAControlProvider()) { entry in
            ControlWidgetButton(action: FeatureAIncrement(item: entry.item ?? .init(id: "unavailable", name: "未選択"))) {
                Label(entry.item.map { "A \($0.name): \(entry.value ?? 0)" } ?? "A 利用不可", systemImage: "plus.circle")
            }
        }
        .displayName("操作検証 A")
        .description("選択したAの項目を1増やします")
    }
}

@MainActor
public enum FeatureAMiniApp {
    public static func definition(store: FeatureAStore) -> MiniAppDefinition {
        MiniAppDefinition(id: FeatureAStore.owner, title: "操作検証 A", systemImage: "a.square",
            backup: .init(id: FeatureAStore.owner, export: {
                .init(id: FeatureAStore.owner, schemaVersion: 1, payload: try JSONEncoder().encode(store.state.read().value))
            }, prepare: { entry in
                guard entry.schemaVersion == 1 else { throw MiniAppBackupError.invalidEntry }
                let value = try JSONDecoder().decode(FeatureAState.self, from: entry.payload)
                return .init { try store.state.replaceForRestore(value) }
            }),
            removal: .init(id: FeatureAStore.owner, dataDescription: "操作検証Aの全項目") { try store.state.remove() },
            externalAccess: store.state.externalAccess(initialValue: .initial)
        ) { _ in FeatureARoot(store: store) }
    }
}

private struct FeatureARoot: View {
    let store: FeatureAStore
    @Environment(\.scenePhase) private var phase
    @State private var text = "読み込み中"
    var body: some View {
        VStack(spacing: 20) {
            Text(text).accessibilityIdentifier("interactive-a.values")
            Button("値を再読込み", action: refresh)
            Button("same-idを削除") {
                do { try store.deleteFirstItem(); reload(); refresh() }
                catch { text = "error: \(error)" }
            }
            .accessibilityIdentifier("interactive-a.delete")
        }
        .task { refresh() }
        .onChange(of: phase) { _, value in if value == .active { refresh() } }
    }
    private func refresh() {
        do {
            text = try store.entities().map { "\($0.name): \(try store.value(for: $0))" }.joined(separator: "\n")
        } catch { text = "error: \(error)" }
    }
    private func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: FeatureAWidget.kind)
        ControlCenter.shared.reloadControls(ofKind: FeatureAControl.kind)
    }
}
