import AppIntents
import Foundation
import JibunKitCore
import SwiftUI
import WidgetKit

public struct FeatureBState: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public var identity = UUID()
        public var value: Int
    }
    public var items: [String: Item]
    public static var initial: Self { .init(items: ["same-id": .init(value: 20), "second-id": .init(value: 40)]) }
}

public struct FeatureBStore: Sendable {
    public static let owner = MiniAppID("interactive-b")
    public let state: MiniAppSharedState<FeatureBState>
    public init(state: MiniAppSharedState<FeatureBState>) { self.state = state }
    public static func shared() throws -> Self { .init(state: try .shared(owner: owner)) }

    public func entities() throws -> [FeatureBItem] {
        let snapshot = try state.read()
        return snapshot.value.items.sorted { $0.key < $1.key }.map { key, item in
            FeatureBItem(id: "\(snapshot.generation.uuidString)/\(item.identity.uuidString)/\(key)", name: key)
        }
    }

    public func value(for entity: FeatureBItem) throws -> Int {
        let snapshot = try state.read()
        let key = try resolve(entity, in: snapshot)
        guard let item = snapshot.value.items[key] else { throw FeatureBError.missingItem }
        return item.value
    }

    @discardableResult
    public func increment(_ entity: FeatureBItem, failBeforeCommit: Bool = false) throws -> Int {
        let snapshot = try state.read()
        let key = try resolve(entity, in: snapshot)
        return try state.update(generation: snapshot.generation) { value in
            guard var item = value.items[key], item.identity == snapshot.value.items[key]?.identity else {
                throw FeatureBError.missingItem
            }
            let (next, overflow) = item.value.addingReportingOverflow(1)
            guard !overflow else { throw FeatureBError.overflow }
            item.value = next
            value.items[key] = item
            if failBeforeCommit { throw FeatureBError.injected }
            return next
        }
    }

    public func deleteFirstItem() throws {
        let snapshot = try state.read()
        try state.update(generation: snapshot.generation) { $0.items["same-id"] = nil }
    }

    private func resolve(_ entity: FeatureBItem, in snapshot: MiniAppSharedState<FeatureBState>.Snapshot) throws -> String {
        let parts = entity.id.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == snapshot.generation.uuidString,
              let item = snapshot.value.items[parts[2]], parts[1] == item.identity.uuidString else {
            throw FeatureBError.missingItem
        }
        return parts[2]
    }
}

public enum FeatureBError: Error { case missingItem, overflow, injected }

public struct FeatureBItem: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bの項目")
    public static let defaultQuery = FeatureBQuery()
    public var id: String
    public var name: String
    public var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct FeatureBQuery: EntityQuery {
    public init() {}
    public func entities(for identifiers: [String]) async throws -> [FeatureBItem] {
        let items = try FeatureBStore.shared().entities()
        return identifiers.compactMap { id in items.first { $0.id == id } }
    }
    public func suggestedEntities() async throws -> [FeatureBItem] { try FeatureBStore.shared().entities() }
}

public struct FeatureBWidgetConfiguration: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "操作検証Bの項目"
    @Parameter(title: "項目") public var item: FeatureBItem?
    public init() {}
}

public struct FeatureBControlConfiguration: ControlConfigurationIntent {
    public static let title: LocalizedStringResource = "操作検証BのControl"
    @Parameter(title: "項目") public var item: FeatureBItem?
    public init() {}
}

public struct FeatureBIncrement: AppIntent {
    public static let title: LocalizedStringResource = "操作検証Bを増やす"
    public static let openAppWhenRun = false
    @Parameter(title: "項目") public var item: FeatureBItem
    public init() {}
    public init(item: FeatureBItem) { self.item = item }
    public func perform() async throws -> some IntentResult {
        try Task.checkCancellation()
        try FeatureBStore.shared().increment(item)
        WidgetCenter.shared.reloadTimelines(ofKind: FeatureBWidget.kind)
        ControlCenter.shared.reloadControls(ofKind: FeatureBControl.kind)
        return .result()
    }
}

public struct FeatureBIntents: AppIntentsPackage {}

public struct FeatureBEntry: TimelineEntry, Sendable {
    public let date: Date
    public let item: FeatureBItem?
    public let value: Int?
    public static func current(item: FeatureBItem?, store: FeatureBStore) -> Self {
        guard let item, let value = try? store.value(for: item) else {
            return .init(date: .now, item: nil, value: nil)
        }
        return .init(date: .now, item: item, value: value)
    }
}

public struct FeatureBProvider: AppIntentTimelineProvider {
    public init() {}
    public func placeholder(in context: Context) -> FeatureBEntry { .init(date: .now, item: nil, value: nil) }
    public func snapshot(for configuration: FeatureBWidgetConfiguration, in context: Context) async -> FeatureBEntry {
        current(configuration)
    }
    public func timeline(for configuration: FeatureBWidgetConfiguration, in context: Context) async -> Timeline<FeatureBEntry> {
        .init(entries: [current(configuration)], policy: .after(.now.addingTimeInterval(900)))
    }
    private func current(_ configuration: FeatureBWidgetConfiguration) -> FeatureBEntry {
        guard let store = try? FeatureBStore.shared() else { return .init(date: .now, item: nil, value: nil) }
        return .current(item: configuration.item, store: store)
    }
}

public struct FeatureBWidget: Widget {
    public nonisolated static let kind = "com.jibunkit.fixture.interactive-b.widget"
    public init() {}
    public var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: FeatureBWidgetConfiguration.self, provider: FeatureBProvider()) { entry in
            VStack {
                Text("操作検証 B")
                if let item = entry.item, let value = entry.value {
                    Text("\(item.name): \(value)")
                    Button(intent: FeatureBIncrement(item: item)) { Label("+1", systemImage: "plus") }
                } else { Text("項目を選択／アプリの状態を確認") }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("操作検証 B")
        .description("選択したBの項目だけを更新します")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

public struct FeatureBControlProvider: AppIntentControlValueProvider {
    public init() {}
    public func previewValue(configuration: FeatureBControlConfiguration) -> FeatureBEntry {
        .init(date: .now, item: configuration.item, value: 0)
    }
    public func currentValue(configuration: FeatureBControlConfiguration) async throws -> FeatureBEntry {
        .current(item: configuration.item, store: try FeatureBStore.shared())
    }
}

public struct FeatureBControl: ControlWidget {
    public nonisolated static let kind = "com.jibunkit.fixture.interactive-b.control"
    public init() {}
    public var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: FeatureBControlProvider()) { entry in
            ControlWidgetButton(action: FeatureBIncrement(item: entry.item ?? .init(id: "unavailable", name: "未選択"))) {
                Label(entry.item.map { "B \($0.name): \(entry.value ?? 0)" } ?? "B 利用不可", systemImage: "plus.circle")
            }
        }
        .displayName("操作検証 B")
        .description("選択したBの項目を1増やします")
    }
}

@MainActor
public enum FeatureBMiniApp {
    public static func definition(store: FeatureBStore) -> MiniAppDefinition {
        MiniAppDefinition(id: FeatureBStore.owner, title: "操作検証 B", systemImage: "b.square",
            backup: .init(id: FeatureBStore.owner, export: {
                .init(id: FeatureBStore.owner, schemaVersion: 1, payload: try JSONEncoder().encode(store.state.read().value))
            }, prepare: { entry in
                guard entry.schemaVersion == 1 else { throw MiniAppBackupError.invalidEntry }
                let value = try JSONDecoder().decode(FeatureBState.self, from: entry.payload)
                return .init { try store.state.replaceForRestore(value) }
            }),
            removal: .init(id: FeatureBStore.owner, dataDescription: "操作検証Bの全項目") { try store.state.remove() },
            externalAccess: store.state.externalAccess(initialValue: .initial)
        ) { _ in FeatureBRoot(store: store) }
    }
}

private struct FeatureBRoot: View {
    let store: FeatureBStore
    @Environment(\.scenePhase) private var phase
    @State private var text = "読み込み中"
    var body: some View {
        VStack(spacing: 20) {
            Text(text).accessibilityIdentifier("interactive-b.values")
            Button("値を再読込み", action: refresh)
            Button("same-idを削除") {
                do { try store.deleteFirstItem(); reload(); refresh() }
                catch { text = "error: \(error)" }
            }
            .accessibilityIdentifier("interactive-b.delete")
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
        WidgetCenter.shared.reloadTimelines(ofKind: FeatureBWidget.kind)
        ControlCenter.shared.reloadControls(ofKind: FeatureBControl.kind)
    }
}
