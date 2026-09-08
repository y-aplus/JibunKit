#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import OSLog

struct RecordAttachmentsSection: View {
    let store: RecordStore
    @Binding var record: Record
    @State private var importing = false
    @State private var busy = false
    @Binding var preview: URL?
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
                .accessibilityIdentifier("records.attachment.\(attachment.id.uuidString)")
                .swipeActions {
                    Button("削除", role: .destructive) { deleting = attachment; confirming = true }
                }
            }
            attachmentPicker
            if busy { ProgressView() }
            if let error { Text(error).accessibilityIdentifier("records.attachment.error") }
        }
        .disabled(busy)
        .alert("添付ファイルを削除しますか？", isPresented: $confirming, presenting: deleting) { attachment in
            Button("キャンセル", role: .cancel) { deleting = nil }
            Button("削除", role: .destructive) {
                busy = true
                Task {
                    defer { busy = false; deleting = nil }
                    do {
                        try await store.removeAttachment(recordID: record.id, attachmentID: attachment.id)
                        try await refreshRecord()
                    } catch { self.error = "削除できませんでした: \(error.localizedDescription)" }
                }
            }
        } message: { attachment in Text(attachment.name) }
    }

    private var attachmentPicker: some View {
        Button("ファイルを添付", systemImage: "paperclip") { importing = true }
            .accessibilityIdentifier("records.attach")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            Logger(subsystem: "com.jibunkit.records", category: "attachments").notice("File importer completion received")
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
                        try await refreshRecord()
                        Logger(subsystem: "com.jibunkit.records", category: "attachments").notice("Attachment import saved and refreshed")
                    } catch { self.error = "添付できませんでした: \(error.localizedDescription)" }
                }
            }
        }
    }

    private func refreshRecord() async throws {
        guard let updated = try await store.records().first(where: { $0.id == record.id }) else {
            throw RecordStoreError.missingRecord
        }
        record = updated
    }

}
#endif
