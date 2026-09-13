// Generated validation host only. Feature storage is ordinary Codable + files;
// the Integration adapter supplies receipt identity and ownership coordination.
import Foundation
import JibunKitCore
import SwiftUI

@MainActor
enum P1IncomingProbe {
    static let definitions = [make("incoming-a", title: "受信検証 A"), make("incoming-b", title: "受信検証 B")]

    private static func make(_ owner: String, title: String) -> MiniAppDefinition {
        let id = MiniAppID(owner)
        let store = P1IncomingDocumentStore(owner: owner)
        return MiniAppDefinition(id: id, title: title, systemImage: "tray.and.arrow.down",
            incoming: MiniAppIncomingProvider(id: id, typeIdentifiers: ["public.data"]) { receipt, folder in
                // Copy before returning: the delivery folder belongs to Core.
                var parts: [String] = []
                for item in receipt.items {
                    if item.kind == .file {
                        parts.append(try String(contentsOf: folder.appendingPathComponent(item.value), encoding: .utf8))
                    } else { parts.append(item.value) }
                }
                try await store.apply(id: receipt.id, contents: parts.joined(separator: "\n"))
            },
            lifetime: MiniAppFeatureLifetime(id: id),
            removal: MiniAppRemovalProvider(id: id, dataDescription: "受信済みの診断文書") { try await store.remove() }
        ) { _ in P1IncomingProbeView(owner: id, store: store) }
    }
}

private actor P1IncomingDocumentStore {
    struct Document: Codable, Sendable { let id: UUID; let contents: String }
    private let owner: String
    private var failAfterCommit = false
    private var delayNext = false
    init(owner: String) { self.owner = owner }

    private var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("P1Incoming/" + owner + "/documents.json")
    }
    func documents() throws -> [Document] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([Document].self, from: Data(contentsOf: file))
    }
    func failNextAfterCommit() { failAfterCommit = true }
    func delayNextApply() { delayNext = true }
    func apply(id: UUID, contents: String) async throws {
        if delayNext {
            delayNext = false
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        try Task.checkCancellation()
        var saved = try documents()
        guard !saved.contains(where: { $0.id == id }) else { return }
        saved.append(Document(id: id, contents: contents))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: file, options: .atomic)
        if failAfterCommit {
            failAfterCommit = false
            throw NSError(domain: "P1Incoming", code: 1, userInfo: [NSLocalizedDescriptionKey: "診断: 保存後の応答失敗（再試行でも二重保存しません）"])
        }
    }
    func remove() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}

private struct P1IncomingProbeView: View {
    let owner: MiniAppID
    let store: P1IncomingDocumentStore
    @State private var count = 0
    @State private var contents = ""
    @State private var status = "loading"
    @State private var file: URL?

    var body: some View {
        List {
            Text("\(count)").accessibilityIdentifier("p1.incoming.count")
            Text(contents).accessibilityIdentifier("p1.incoming.contents")
            Text(status).accessibilityIdentifier("p1.incoming.status")
            Button("保存後に一度失敗させる") {
                Task { await store.failNextAfterCommit(); status = "failure armed" }
            }.accessibilityIdentifier("p1.incoming.fail")
            Button("次の取込みを遅らせる") {
                Task { await store.delayNextApply(); status = "delay armed" }
            }.accessibilityIdentifier("p1.incoming.delay")
            Button("A/Bへ受信を保存") {
                Task {
                    do {
                        let inbox = try MiniAppIncomingStore.shared()
                        try await Task.detached {
                            _ = try inbox.enqueue(for: MiniAppID("incoming-a"), inputs: [.text("A incoming text")])
                            _ = try inbox.enqueue(for: MiniAppID("incoming-b"), inputs: [.text("B incoming text")])
                        }.value
                        status = "A/B queued"
                    } catch { status = "failed: \(error)" }
                }
            }.accessibilityIdentifier("p1.incoming.seed")
            Section("OS共有シート（実機確認）") {
                ShareLink("文字列を共有", item: "Shared text from " + owner.rawValue)
                ShareLink("URLを共有", item: URL(string: "https://example.com/" + owner.rawValue)!)
                if let file { ShareLink("ファイルを共有", item: file) }
            }
        }
        .task {
            do {
                let saved = try await store.documents()
                count = saved.count
                contents = saved.map(\.contents).joined(separator: "\n")
                let export = FileManager.default.temporaryDirectory.appendingPathComponent(owner.rawValue + "-share.txt")
                try Data(("Shared file from " + owner.rawValue).utf8).write(to: export, options: .atomic)
                file = export
                status = "loaded"
            } catch { status = "failed: \(error)" }
        }
    }
}
