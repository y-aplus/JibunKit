#if os(iOS)
import SwiftUI

public struct RecordsRootView: View {
    private let store: RecordStore
    @State private var records: [Record] = []
    @State private var query = ""
    @State private var editing: Record?
    @State private var deleting: Record?
    @State private var confirmingDelete = false
    @State private var error: String?

    public init(store: RecordStore) { self.store = store }

    private var visible: [Record] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? records : records.filter {
            $0.title.localizedStandardContains(text) || $0.body.localizedStandardContains(text)
        }
    }

    public var body: some View {
        List {
            if let error { Text(error).accessibilityIdentifier("records.error") }
            ForEach(visible) { record in
                NavigationLink(value: record.id) {
                    VStack(alignment: .leading) {
                        Text(record.title)
                        if !record.body.isEmpty { Text(record.body).lineLimit(1).foregroundStyle(.secondary) }
                    }
                }
                .accessibilityIdentifier("records.row.\(record.id)")
                .swipeActions {
                    Button("削除", role: .destructive) { deleting = record; confirmingDelete = true }
                }
            }
        }
        .overlay {
            if visible.isEmpty && error == nil {
                ContentUnavailableView(query.isEmpty ? "記録はまだありません" : "一致する記録がありません", systemImage: "doc.text")
            }
        }
        .searchable(text: $query, prompt: "記録を検索")
        .navigationTitle("記録")
        .toolbar { Button("追加", systemImage: "plus") { editing = Record(title: "") }.accessibilityIdentifier("records.add") }
        .task { await reload() }
        .sheet(item: $editing, onDismiss: { Task { await reload() } }) { record in
            RecordEditor(store: store, record: record)
        }
        .navigationDestination(for: UUID.self) { id in
            if let record = records.first(where: { $0.id == id }) {
                List {
                    Section("本文") { Text(record.body).accessibilityIdentifier("records.body") }
                    RecordAttachmentsSection(store: store, record: record) { await reload() }
                }
                .navigationTitle(record.title)
                .toolbar { Button("編集") { editing = record }.accessibilityIdentifier("records.edit") }
            } else { ContentUnavailableView("記録が見つかりません", systemImage: "doc.questionmark") }
        }
        .alert("記録を削除しますか？", isPresented: $confirmingDelete, presenting: deleting) { record in
            Button("キャンセル", role: .cancel) { deleting = nil }
            Button("削除", role: .destructive) {
                Task {
                    do { try await store.delete(id: record.id); await reload() }
                    catch { self.error = "削除できませんでした: \(error.localizedDescription)" }
                    deleting = nil
                }
            }
        } message: { record in Text("「\(record.title)」と添付ファイルを削除します。") }
    }

    private func reload() async {
        do { records = try await store.records(); error = nil }
        catch { self.error = "記録を読み込めませんでした: \(error.localizedDescription)" }
    }
}

private struct RecordEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: RecordStore
    @State var record: Record
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("タイトル", text: $record.title).accessibilityIdentifier("records.title")
                TextEditor(text: $record.body).frame(minHeight: 160).accessibilityIdentifier("records.editor.body")
                if let error { Text(error) }
            }
            .disabled(busy)
            .navigationTitle("記録を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        busy = true
                        Task {
                            defer { busy = false }
                            do { try await store.save(record); dismiss() }
                            catch { self.error = "保存できませんでした: \(error.localizedDescription)" }
                        }
                    }
                    .disabled(busy || record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("records.save")
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }
}
#endif
