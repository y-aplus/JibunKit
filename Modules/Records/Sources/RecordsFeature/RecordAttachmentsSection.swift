#if os(iOS)
import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct RecordAttachmentsSection: View {
    let store: RecordStore
    let record: Record
    let refresh: @MainActor () async -> Void
    @State private var importing = false
    @State private var busy = false
    @State private var preview: URL?
    @State private var deleting: RecordAttachment?
    @State private var confirming = false
    @State private var error: String?

    var body: some View {
        Section("添付ファイル") {
            ForEach(record.attachments) { attachment in
                Button(attachment.name) {
                    busy = true
                    error = nil
                    Task {
                        defer { busy = false }
                        do {
                            preview = try await store.copyAttachment(recordID: record.id, attachmentID: attachment.id,
                                to: FileManager.default.temporaryDirectory.appendingPathComponent("RecordsPreviews", isDirectory: true))
                        } catch { self.error = "添付ファイルを開けませんでした: \(error.localizedDescription)" }
                    }
                }
                .swipeActions {
                    Button("削除", role: .destructive) { deleting = attachment; confirming = true }
                }
            }
            Button("ファイルを添付", systemImage: "paperclip") { importing = true }
                .accessibilityIdentifier("records.attach")
            if busy { ProgressView() }
            if let error { Text(error).accessibilityIdentifier("records.attachment.error") }
        }
        .disabled(busy)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            switch result {
            case .failure(let error): self.error = "読み込めませんでした: \(error.localizedDescription)"
            case .success(let url):
                busy = true
                error = nil
                Task {
                    defer { busy = false }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        try await store.importAttachment(to: record.id, from: url)
                        await refresh()
                    } catch { self.error = "添付できませんでした: \(error.localizedDescription)" }
                }
            }
        }
        .quickLookPreview($preview)
        .onChange(of: preview) { old, new in
            if let old, old != new { try? FileManager.default.removeItem(at: old) }
        }
        .alert("添付ファイルを削除しますか？", isPresented: $confirming, presenting: deleting) { attachment in
            Button("キャンセル", role: .cancel) { deleting = nil }
            Button("削除", role: .destructive) {
                busy = true
                Task {
                    defer { busy = false; deleting = nil }
                    do {
                        try await store.removeAttachment(recordID: record.id, attachmentID: attachment.id)
                        await refresh()
                    } catch { self.error = "削除できませんでした: \(error.localizedDescription)" }
                }
            }
        } message: { attachment in Text(attachment.name) }
    }
}
#endif
