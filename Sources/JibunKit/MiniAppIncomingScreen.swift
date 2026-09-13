#if os(iOS)
import SwiftUI
import JibunKitCore

struct MiniAppIncomingScreen: View {
    @Bindable var navigation: AppNavigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var rows: [Row] = []
    @State private var message: String?
    @State private var operation: Task<Void, Never>?
    @State private var discardTarget: Row?

    private struct Row: Identifiable {
        let id: UUID
        let owner: MiniAppID
        let receipt: MiniAppIncomingReceipt?
    }

    private var destinations: [MiniAppDefinition] {
        guard let prepared = navigation.preparedIncoming else { return [] }
        return MiniAppRegistry.enabled.filter { definition in
            guard let destination = MiniAppRegistry.incomingDestination(for: definition) else { return false }
            return prepared.inputs.allSatisfy { destination.accepts($0.typeIdentifier) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if navigation.isPreparingIncoming {
                    ProgressView("ファイルを読み込んでいます")
                    Button("読み込みをキャンセル") { navigation.discardPreparedIncoming() }
                }
                if let error = navigation.incomingError { Text(error).foregroundStyle(.red) }
                if let message { Text(message).accessibilityIdentifier("incoming.message") }
                if let prepared = navigation.preparedIncoming {
                    Section("受信先を選択（\(prepared.inputs.count)件）") {
                        if destinations.isEmpty { Text("この入力を受け取れる有効なミニアプリがありません。") }
                        ForEach(destinations) { definition in
                            Button(definition.title) { savePrepared(for: definition.id) }
                                .accessibilityIdentifier("incoming.destination.\(definition.id.rawValue)")
                                .disabled(operation != nil)
                        }
                        Button("この受信をキャンセル", role: .cancel) { navigation.discardPreparedIncoming() }
                            .disabled(operation != nil)
                    }
                }
                Section("未取込み") {
                    if rows.isEmpty { Text("未取込みの共有データはありません。") }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(MiniAppRegistry.all.first(where: { $0.id == row.owner })?.title ?? row.owner.rawValue)
                                .font(.headline)
                            if let receipt = row.receipt {
                                Text(receipt.items.map(\.displayName).joined(separator: "、"))
                                Text(receipt.createdAt, style: .date).font(.caption)
                                if MiniAppRegistry.management.isEnabled(row.owner),
                                   MiniAppRegistry.definition(for: row.owner)?.incoming != nil {
                                    Button("取り込む / 再試行") { deliver(row) }
                                        .accessibilityIdentifier("incoming.apply.\(row.owner.rawValue)")
                                } else { Text("受信先が無効、またはこの版に登録されていません。データは保持されています。") }
                            } else { Text("受信データを読み取れません。破損した項目を破棄することはできます。") }
                            Button("破棄", role: .destructive) { discardTarget = row }
                        }
                        .disabled(operation != nil)
                    }
                }
            }
            .navigationTitle("受信")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.disabled(operation != nil || navigation.preparedIncoming != nil || navigation.isPreparingIncoming)
                }
                if operation != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("処理をキャンセル") { operation?.cancel() }
                    }
                }
            }
            .confirmationDialog("この未取込みデータを破棄しますか？", isPresented: Binding(
                get: { discardTarget != nil }, set: { if !$0 { discardTarget = nil } }
            ), titleVisibility: .visible) {
                if let target = discardTarget {
                    Button("破棄する", role: .destructive) { discard(target) }
                }
            } message: { Text("取り込まれたミニアプリのデータや、他の受信は変更しません。") }
            .task { await reload() }
            .refreshable { await reload() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reload() } } }
        }
        .interactiveDismissDisabled(operation != nil || navigation.preparedIncoming != nil || navigation.isPreparingIncoming)
    }

    private func reload() async {
        do {
            let inbox = try MiniAppRegistry.incomingStore.get()
            let (listings, failures) = try await Task.detached {
                var listings: [(MiniAppID, MiniAppIncomingStore.Listing)] = []
                var failures: [String] = []
                for owner in try inbox.ownersWithReceipts() {
                    do { listings.append((owner, try inbox.pending(for: owner))) }
                    catch { failures.append("\(owner.rawValue): \(error.localizedDescription)") }
                }
                return (listings, failures)
            }.value
            rows = listings.flatMap { owner, listing in
                listing.receipts.map { Row(id: $0.id, owner: owner, receipt: $0) }
                    + listing.unreadableIDs.map { Row(id: $0, owner: owner, receipt: nil) }
            }
            if let error = MiniAppRegistry.incomingCatalogError { message = "受信先の更新に失敗しました: \(error)" }
            if !failures.isEmpty { message = "一部の受信先を読み取れません: " + failures.joined(separator: "、") }
        } catch { message = error.localizedDescription }
    }

    private func savePrepared(for owner: MiniAppID) {
        guard operation == nil, let prepared = navigation.preparedIncoming else { return }
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                guard MiniAppRegistry.management.isEnabled(owner) else { throw MiniAppIncomingError.unavailableOwner(owner.rawValue) }
                let inbox = try MiniAppRegistry.incomingStore.get()
                let task = Task.detached { try inbox.enqueue(for: owner, inputs: prepared.inputs) }
                _ = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                navigation.discardPreparedIncoming()
                message = "受信を保存しました。対象の「取り込む / 再試行」から取り込めます。"
                await reload()
            } catch is CancellationError { message = "キャンセルしました。受信先は変更していません。" }
            catch { message = error.localizedDescription }
        }
    }

    private func deliver(_ row: Row) {
        guard operation == nil, let definition = MiniAppRegistry.definition(for: row.owner), let provider = definition.incoming else { return }
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                guard MiniAppRegistry.management.isEnabled(row.owner) else { throw MiniAppIncomingError.unavailableOwner(row.owner.rawValue) }
                try await MiniAppIncomingDelivery.shared.deliver(id: row.id, provider: provider,
                    lifetime: definition.lifetime, inbox: MiniAppRegistry.incomingStore.get())
                message = "取り込みました。"
            } catch is CancellationError { message = "キャンセルしました。未完了の受信は保持しています。" }
            catch { message = "取り込みに失敗しました。受信を保持しています: \(error.localizedDescription)" }
            await reload()
        }
    }

    private func discard(_ row: Row) {
        guard operation == nil else { return }
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                let inbox = try MiniAppRegistry.incomingStore.get()
                try await MiniAppIncomingDelivery.shared.discard(id: row.id, owner: row.owner, inbox: inbox)
                message = "未取込みデータを破棄しました。"
            } catch { message = error.localizedDescription }
            await reload()
        }
    }
}
#endif
