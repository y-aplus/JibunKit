import SwiftUI
import JibunKitCore
import JibunKitBackup
import CounterFeature
import ReminderFeature

@main
struct BackupHarnessApp: App {
    var body: some Scene { WindowGroup { HarnessScreen() } }
}

private struct ImportedFixture: Identifiable {
    let id = UUID()
    var backup: MiniAppBackup? = nil
    var archive: ImportedMiniAppBackup? = nil
    var failReminder = false
}

private struct HarnessScreen: View {
    private let counter = CounterStore(context: MiniAppContext(id: .counter), suiteName: "jibunkit.backup-harness.data")
    private let reminder = ReminderStore(context: MiniAppContext(id: .reminder),
                                        infoDictionary: ["JibunKitAppGroup": "jibunkit.backup-harness.data"])
    @State private var fixture: ImportedFixture?
    @State private var values = ""
    @State private var ready = false
    @State private var presentingFixture = false
    @State private var fileValue = ""
    private let fileStore = HarnessFileStore()

    private var definitions: [MiniAppDefinition] {
        [MiniAppDefinition(id: .counter, title: "カウンター", systemImage: "number", backup: counter.backupProvider) { _ in EmptyView() },
         MiniAppDefinition(id: .reminder, title: "リマインダー", systemImage: "bell", backup: reminder.backupProvider) { _ in EmptyView() },
         MiniAppDefinition(id: MiniAppID("files"), title: "添付テスト", systemImage: "doc", fileBackup: fileStore.provider) { _ in EmptyView() }]
    }

    var body: some View {
        VStack {
            Text(values).accessibilityIdentifier("harness.values")
            Text(fileValue).accessibilityIdentifier("harness.file-value")
            Button("正常なバックアップ") { present(invalid: false) }.accessibilityIdentifier("harness.valid")
            Button("不正なバックアップ") { present(invalid: true) }.accessibilityIdentifier("harness.invalid")
            Button("適用時に失敗") { present(invalid: false, failReminder: true) }.accessibilityIdentifier("harness.failure")
            Button("添付バックアップ") { presentFiles() }.accessibilityIdentifier("harness.files")
            Button("添付を変更") {
                do {
                    try fileStore.save(Data("changed attachment".utf8))
                    Task { await refresh() }
                } catch { values = "Write failed: \(error)" }
            }.accessibilityIdentifier("harness.change-file")
        }
        .disabled(!ready || presentingFixture)
        .task {
            do {
                if !ProcessInfo.processInfo.arguments.contains("--preserve") {
                    let seed = MiniAppBackupEntry(id: .counter, schemaVersion: 1, payload: Data(#"{"value":9}"#.utf8))
                    try await counter.backupProvider.prepareRestore(seed).apply()
                    try await reminder.saveMessage("keep")
                    try fileStore.save(Data("live attachment".utf8))
                }
                await refresh()
                ready = true
            } catch { values = "Setup failed: \(error)" }
        }
        .sheet(item: $fixture, onDismiss: {
            Task {
                await refresh()
                presentingFixture = false
            }
        }) { item in
            BackupScreen(definitions: item.failReminder ? failingDefinitions : definitions,
                         importedBackup: item.backup, importedArchive: item.archive)
        }
    }

    private var failingDefinitions: [MiniAppDefinition] {
        let failing = MiniAppBackupProvider(id: .reminder, export: reminder.backupProvider.export, prepare: { _ in
            MiniAppPreparedRestore { throw CocoaError(.fileWriteNoPermission) }
        })
        return [definitions[0], MiniAppDefinition(id: .reminder, title: "リマインダー", systemImage: "bell", backup: failing) { _ in EmptyView() }]
    }

    private func present(invalid: Bool, failReminder: Bool = false) {
        do {
            let counterPayload = invalid ? #"{"value":"invalid"}"# : #"{"value":3}"#
            let backup = try MiniAppBackup(entries: [
                MiniAppBackupEntry(id: .counter, schemaVersion: 1, payload: Data(counterPayload.utf8)),
                MiniAppBackupEntry(id: .reminder, schemaVersion: 1, payload: Data(#"{"message":"old"}"#.utf8)),
            ])
            let imported = try MiniAppBackup.decode(backup.encoded())
            presentingFixture = true
            fixture = ImportedFixture(backup: imported, failReminder: failReminder)
        } catch { values = "Fixture failed: \(error)" }
    }

    private func refresh() async {
        do {
            values = "\(try await counter.currentValue())|\(try await reminder.currentMessage())"
            fileValue = String(decoding: try fileStore.read(), as: UTF8.self)
        }
        catch { values = "Read failed: \(error)" }
    }

    private func presentFiles() {
        ready = false
        let payload = counter.backupProvider
        Task {
            defer { ready = true }
            do {
                let imported = try await Task.detached {
                    let fileProvider = MiniAppFileBackupProvider(id: MiniAppID("files"), export: { destination in
                        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                        try Data("restored attachment".utf8).write(to: destination.appendingPathComponent("asset"))
                        return 1
                    }, prepare: { _ in MiniAppPreparedRestore {} })
                    let file = try await MiniAppBackupArchive.export(selected: [.counter, MiniAppID("files")],
                        providers: [payload], fileProviders: [fileProvider])
                    return try MiniAppBackupArchive.load(from: file.url)
                }.value
                presentingFixture = true
                fixture = ImportedFixture(archive: imported)
            } catch { values = "File fixture failed: \(error)" }
        }
    }
}

/// Test-only file provider exercising the production screen and ZIP decoder.
private struct HarnessFileStore: Sendable {
    private var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("harness-attachment")
    }
    func read() throws -> Data { try Data(contentsOf: url) }
    func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    var provider: MiniAppFileBackupProvider {
        MiniAppFileBackupProvider(id: MiniAppID("files"), export: { destination in
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination.appendingPathComponent("asset"))
            return 1
        }, prepare: { entry in
            guard entry.schemaVersion == 1 else { throw MiniAppBackupError.unsupportedSchema(entry.schemaVersion) }
            let data = try Data(contentsOf: entry.directory.appendingPathComponent("asset"))
            return MiniAppPreparedRestore { try save(data) }
        })
    }
}
