#if os(iOS)
import JibunKitCore
import SwiftUI
import UniformTypeIdentifiers

struct BackupScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exportIDs: Set<MiniAppID> = []
    @State private var restoreIDs: Set<MiniAppID> = []
    @State private var imported: MiniAppBackup?
    @State private var document: BackupDocument?
    @State private var exportFilename = "JibunKit-backup"
    @State private var importing = false
    @State private var exporting = false
    @State private var confirming = false
    @State private var pending: MiniAppRestorePlan?
    @State private var busy = false
    @State private var status: String?

    private let definitions: [MiniAppDefinition]

    init(definitions: [MiniAppDefinition], importedBackup: MiniAppBackup? = nil) {
        self.definitions = definitions
        _imported = State(initialValue: importedBackup)
    }
    private var providers: [MiniAppBackupProvider] { definitions.compactMap(\.backup) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(definitions) { definition in
                        if definition.backup != nil {
                            Toggle(definition.title, isOn: selection(definition.id, in: $exportIDs))
                                .accessibilityIdentifier("backup.export.\(definition.id.rawValue)")
                        } else {
                            LabeledContent(definition.title, value: "バックアップ未対応")
                        }
                    }
                    Button("選択したアプリを書き出す") { exportSelected() }
                        .disabled(exportIDs.isEmpty)
                        .accessibilityIdentifier("backup.export")
                } header: { Text("バックアップ") }
                footer: { Text("選んだアプリのデータをファイルに保存します。ファイルは暗号化されません。") }

                Section {
                    Button("バックアップを読み込む") {
                        imported = nil
                        restoreIDs = []
                        pending = nil
                        status = nil
                        importing = true
                    }
                    .accessibilityIdentifier("backup.import")
                    if let imported {
                        LabeledContent("作成日時", value: imported.createdAt.formatted(date: .abbreviated, time: .shortened))
                        ForEach(imported.entries, id: \.id) { entry in
                            let id = MiniAppID(entry.id)
                            if let definition = definitions.first(where: { $0.id == id }), definition.backup != nil {
                                Toggle(definition.title, isOn: selection(id, in: $restoreIDs))
                                    .accessibilityIdentifier("backup.restore.\(entry.id)")
                            } else {
                                LabeledContent(title(id), value: "この構成では復元できません")
                            }
                        }
                        Button("選択したアプリを復元") { prepareRestore(imported) }
                            .disabled(restoreIDs.isEmpty)
                            .accessibilityIdentifier("backup.restore")
                    }
                } header: { Text("復元") }
                footer: { Text("選んだアプリの現在のデータを置き換えます。選ばなかったアプリは変更しません。") }

                if busy { ProgressView("処理中…") }
                if let status { Section { Text(status).accessibilityIdentifier("backup.status") } }
            }
            .disabled(busy)
            .navigationTitle("バックアップと復元")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.disabled(busy)
                }
            }
            .interactiveDismissDisabled(busy)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): load(url)
                case .failure: status = "ファイルを読み込めませんでした。保存データは変更していません。"
                }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                          defaultFilename: exportFilename) { result in
                switch result {
                case .success: status = "バックアップを書き出しました。"
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { status = "書き出せませんでした。" }
                }
                document = nil
            }
            .alert("現在のデータを置き換えますか？", isPresented: $confirming) {
                Button("キャンセル", role: .cancel) { pending = nil }
                Button("置き換えて復元", role: .destructive) { restore() }
            } message: {
                Text((pending?.ids.map(title).joined(separator: "、") ?? "") +
                     "をバックアップの内容に戻します。実行中に失敗すると、一部だけ復元される場合があります。")
            }
        }
    }

    private func title(_ id: MiniAppID) -> String {
        definitions.first { $0.id == id }?.title ?? id.rawValue
    }

    private func selection(_ id: MiniAppID, in values: Binding<Set<MiniAppID>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(id) }, set: { selected in
            if selected { values.wrappedValue.insert(id) } else { values.wrappedValue.remove(id) }
        })
    }

    private func exportSelected() {
        let selected = providers.filter { exportIDs.contains($0.id) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        exportFilename = "JibunKit-backup-\(formatter.string(from: Date()))"
        busy = true
        status = nil
        Task {
            defer { busy = false }
            do {
                let data = try await Task.detached {
                    var entries: [MiniAppBackupEntry] = []
                    for provider in selected {
                        entries.append(try await provider.exportEntry())
                    }
                    return try MiniAppBackup(entries: entries).encoded()
                }.value
                document = BackupDocument(data: data)
                exporting = true
            } catch { status = "バックアップを作成できませんでした。ファイルは書き出していません。" }
        }
    }

    private func load(_ url: URL) {
        busy = true
        Task {
            defer { busy = false }
            do {
                imported = try await Task.detached {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try MiniAppBackup.decode(Data(contentsOf: url))
                }.value
                status = "復元するアプリを選んでください。まだ保存データは変更していません。"
            } catch { status = "対応するバックアップを読み込めませんでした。保存データは変更していません。" }
        }
    }

    private func prepareRestore(_ backup: MiniAppBackup) {
        let selected = restoreIDs
        let available = providers
        busy = true
        status = nil
        Task {
            defer { busy = false }
            do {
                pending = try await Task.detached {
                    try MiniAppRestorePlan(backup: backup, selected: selected, providers: available)
                }.value
                confirming = true
            } catch { status = "選んだデータを復元できません。内容や対応する版を確認してください。保存データは変更していません。" }
        }
    }

    private func restore() {
        guard let plan = pending else { return }
        pending = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                try await plan.apply()
                status = plan.ids.map(title).joined(separator: "、") + "を復元しました。"
                imported = nil
                restoreIDs = []
            } catch let error as MiniAppRestoreFailure {
                let completed = error.completed.map(title).joined(separator: "、")
                status = "復元を中断しました。完了済み: \(completed.isEmpty ? "なし" : completed)。\(title(error.failed))で失敗しました。このアプリの状態を確認してください。後続のアプリは変更していません。"
            } catch { status = "復元に失敗しました。アプリの状態を確認してください。" }
        }
    }
}
#endif
