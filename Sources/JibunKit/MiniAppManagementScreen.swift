#if os(iOS)
import JibunKitCore
import SwiftUI

struct MiniAppManagementScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: MiniAppDefinition?
    @State private var errorMessage: String?
    private let management = MiniAppRegistry.management

    var body: some View {
        NavigationStack {
            List {
                ForEach(MiniAppRegistry.all) { definition in
                    Section {
                        Text(statusText(management.status(for: definition.id)))
                            .accessibilityIdentifier("management.status.\(definition.id.rawValue)")
                        if let failure = management.failures[definition.id] {
                            Text("\(stageText(failure.stage))で失敗しました。\(failure.message)")
                                .foregroundStyle(.red)
                        }
                        if let stage = management.stages[definition.id] {
                            ProgressView(stageText(stage))
                            if stage == .stopping, let runtime = definition.lifetime?.runtime {
                                TimelineView(.periodic(from: .now, by: 1)) { _ in
                                    let progress = runtime.shutdownProgress
                                    Text("終了待ち: 処理 \(progress.pendingTaskCount) 件、解放 \(progress.remainingCleanupCount) 件")
                                        .font(.caption)
                                }
                            }
                        } else {
                            actions(for: definition)
                        }
                        ForEach(definition.permissions) { permission in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(permission.title).font(.headline)
                                Text(permission.purpose)
                                Text("拒否した場合: " + permission.deniedBehavior).font(.caption)
                                Picker("このアプリでの利用", selection: Binding(
                                    get: { MiniAppRegistry.consents.consent(for: definition.id, permissionID: permission.id) },
                                    set: { MiniAppRegistry.consents.setConsent($0, for: definition.id, permissionID: permission.id) }
                                )) {
                                    Text("未確認").tag(MiniAppConsent.notDetermined)
                                    Text("許可").tag(MiniAppConsent.allowed)
                                    Text("拒否").tag(MiniAppConsent.denied)
                                }
                                .pickerStyle(.menu)
                                .accessibilityIdentifier("management.consent.\(definition.id.rawValue).\(permission.id)")
                                .disabled(!management.isEnabled(definition.id))
                            }
                        }
                    } header: {
                        Label(definition.title, systemImage: definition.systemImage)
                    }
                }
                Section {
                    Text("利用同意はミニアプリごとに保存します。iOSの権限はJibunKit全体で共有され、ここでの許可だけでは変更されません。")
                    Text("削除は登録と所有データを取り除きます。組み込まれたコードを取り除くには再ビルドが必要です。")
                }
            }
            .navigationTitle("ミニアプリの管理")
            .toolbar { Button("閉じる") { dismiss() }.disabled(!management.stages.isEmpty) }
            .interactiveDismissDisabled(!management.stages.isEmpty)
            .alert("所有データを削除しますか？", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), presenting: deleting) { definition in
                Button("キャンセル", role: .cancel) { deleting = nil }
                Button("削除", role: .destructive) {
                    deleting = nil
                    perform { try await management.remove(definition.id) }
                }
            } message: { definition in
                Text("\(definition.title): \(definition.removal?.dataDescription ?? "")\n通知・検索の登録と利用同意も削除します。他のミニアプリのデータは変更しません。")
            }
            .alert("処理を完了できません", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("閉じる", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    @ViewBuilder
    private func actions(for definition: MiniAppDefinition) -> some View {
        let status = management.status(for: definition.id)
        if status == .enabled || status == .disabling {
            Button(status == .disabling ? "無効化を再試行" : "無効化（データを保持）") {
                perform { try await management.disable(definition.id) }
            }
            .accessibilityIdentifier("management.disable.\(definition.id.rawValue)")
        } else if status == .disabled || status == .removed {
            Button(status == .removed ? "初期状態で再登録" : "再有効化") {
                perform { try await management.enable(definition.id) }
            }
            .accessibilityIdentifier("management.enable.\(definition.id.rawValue)")
        }
        if status != .removed {
            if management.canRemove(definition.id) {
                Button(status == .removing ? "削除を再試行" : "登録と所有データを削除", role: .destructive) {
                    deleting = definition
                }
                .accessibilityIdentifier("management.delete.\(definition.id.rawValue)")
            } else {
                Text("このアプリは削除するデータをまだ宣言していません。無効化は利用できます。")
                    .font(.caption)
            }
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        // The operation outlives the button/view; management persists its intent.
        Task { @MainActor in
            do { try await operation() }
            catch { errorMessage = String(describing: error) }
        }
    }

    private func statusText(_ status: MiniAppManagement.Status?) -> String {
        switch status {
        case .enabled: "有効"
        case .disabled: "無効（データを保持）"
        case .removed: "削除済み"
        case .disabling: "無効化が未完了。新しい起動は停止しています。"
        case .removing: "削除が未完了。再試行で残りの処理を完了してください。"
        case nil: "未登録"
        }
    }

    private func stageText(_ stage: MiniAppManagement.Stage) -> String {
        switch stage {
        case .reservation: "保存領域の利用確認"
        case .stopping: "所有処理の終了"
        case .unregistering: "通知・検索などの登録解除"
        case .deletingData: "所有データの削除"
        case .clearingConsent: "利用同意の削除"
        case .enabling: "登録の再有効化"
        }
    }
}
#endif
