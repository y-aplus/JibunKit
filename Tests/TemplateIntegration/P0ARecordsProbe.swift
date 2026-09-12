// Runs real Records storage through host admission/lifetime adapters in the CI host.
import SwiftUI
import Observation
import JibunKitCore
import RecordsFeature

@MainActor
enum P0ARecordsProbe {
    static let definition = MiniAppDefinition(id: MiniAppID("p0-records"), title: "P0 Records",
        systemImage: "doc.text") { _ in ProbeView() }

    @MainActor
    @Observable
    fileprivate final class RecordsProbeState {
        var result = "idle"
        var running = false
        var startsA = 0
        var startsB = 0

        func run() async {
            guard !running else { return }
            running = true
            startsA = 0
            startsB = 0
            result = "running"
            let environment = RecordsEnvironment()
            let coordinator = MiniAppRestoreCoordinator()
            let aID = MiniAppID("p0-records-a"), bID = MiniAppID("p0-records-b")
            let aLifetime = MiniAppFeatureLifetime(id: aID) { [weak self] _ in self?.startsA += 1 }
            let bLifetime = MiniAppFeatureLifetime(id: bID) { [weak self] _ in self?.startsB += 1 }
            do {
                let a = try await environment.makeStore(name: "a", legacy: true,
                    boundary: RecordsStoreOperationBoundary(owner: aID, coordinator: coordinator, lifecycle: aLifetime.restoreLifecycle))
                let b = try await environment.makeStore(name: "b", legacy: false,
                    boundary: RecordsStoreOperationBoundary(owner: bID, coordinator: coordinator, lifecycle: bLifetime.restoreLifecycle))
                try await aLifetime.start()
                try await bLifetime.start()
                try await b.save(Record(title: "Other"))
                let migrated = try await a.migrateIfNeeded()
                let schema = try await environment.schema(name: "a")
                guard migrated, schema == 2 else { throw ProbeFailure.migration }
                let original = try await a.records()[0]
                let attachment = original.attachments[0]
                let provider = RecordsBackup.provider(store: a, id: aID)
                let snapshotURL = await environment.snapshotURL()
                let snapshot = try await provider.exportEntry(to: snapshotURL, coordinator: coordinator)
                var edited = original
                edited.title = "Changed"
                try await a.save(edited)
                let plan = try await environment.prepare(snapshot, provider: provider)
                try await environment.removeSnapshotAttachment(snapshot.directory, id: attachment.id)
                do {
                    try await plan.apply(lifecycles: [aID: aLifetime.restoreLifecycle], coordinator: coordinator)
                    throw ProbeFailure.acceptedCorruptSnapshot
                } catch is MiniAppRestoreFailure { }
                let kept = try await a.records()[0].title
                let liveData = try await a.attachmentData(recordID: original.id, attachmentID: attachment.id)
                guard kept == "Changed", liveData == Data([1, 2, 3]) else { throw ProbeFailure.failedRestoreChangedLiveData }
                try await environment.repairSnapshotAttachment(snapshot.directory, id: attachment.id)
                try await plan.apply(lifecycles: [aID: aLifetime.restoreLifecycle], coordinator: coordinator)
                let restored = try await a.records()[0]
                let restoredData = try await a.attachmentData(recordID: original.id, attachmentID: attachment.id)
                guard restored.id == original.id, restored.createdAt == nil,
                      restoredData == Data([1, 2, 3]) else { throw ProbeFailure.restore }
                try await a.reset()
                let resetCount = try await a.records().count
                let other = try await b.records()[0].title
                result = "schema=\(schema);failed-kept=\(kept);restored=\(restored.title);attachment=\(restoredData.count);reset=\(resetCount);b=\(other);generations=\(startsA)/\(startsB)"
            } catch {
                result = "failed: \(error)"
            }
            await aLifetime.stop()
            await bLifetime.stop()
            await environment.dispose()
            running = false
        }
    }

    private struct ProbeView: View {
        @State private var state = RecordsProbeState()
        var body: some View {
            VStack(spacing: 20) {
                Text(state.result).accessibilityIdentifier("p0.records.result")
                Button("Run Records flow") { Task { await state.run() } }
                    .disabled(state.running)
                    .accessibilityIdentifier("p0.records.run")
            }.padding()
        }
    }

    private enum ProbeFailure: Error {
        case migration, acceptedCorruptSnapshot, failedRestoreChangedLiveData, restore
    }
}

/// Fixture file I/O and preparation run off the main actor, in a unique sandbox.
private actor RecordsEnvironment {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    func makeStore(name: String, legacy: Bool, boundary: any RecordStoreOperationBoundary) throws -> RecordStore {
        let directory = root.appendingPathComponent(name)
        if legacy {
            let assets = directory.appendingPathComponent("attachments")
            try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
            let record = UUID(), attachment = UUID()
            let data = Data("""
            {"version":1,"records":[{"id":"\(record.uuidString)","title":"Legacy","body":"","attachments":[{"id":"\(attachment.uuidString)","name":"old.bin"}]}]}
            """.utf8)
            try data.write(to: directory.appendingPathComponent("records.json"))
            try Data([1, 2, 3]).write(to: assets.appendingPathComponent(attachment.uuidString))
        }
        return try RecordStore(directory: directory, operations: boundary)
    }
    func schema(name: String) throws -> Int {
        struct Header: Decodable { let version: Int }
        return try JSONDecoder().decode(Header.self,
            from: Data(contentsOf: root.appendingPathComponent(name).appendingPathComponent("records.json"))).version
    }
    func snapshotURL() -> URL { root.appendingPathComponent("snapshot") }
    func prepare(_ entry: MiniAppFileBackupEntry, provider: MiniAppFileBackupProvider) throws -> MiniAppRestorePlan {
        try MiniAppRestorePlan(fileEntries: [entry], selected: [entry.id], providers: [provider])
    }
    func removeSnapshotAttachment(_ directory: URL, id: UUID) throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent("attachments").appendingPathComponent(id.uuidString))
    }
    func repairSnapshotAttachment(_ directory: URL, id: UUID) throws {
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("attachments").appendingPathComponent(id.uuidString))
    }
    func dispose() { try? FileManager.default.removeItem(at: root) }
}
