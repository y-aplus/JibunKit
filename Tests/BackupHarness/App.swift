import SwiftUI
import JibunKitCore
import CounterFeature
import ReminderFeature

@main
struct BackupHarnessApp: App {
    var body: some Scene { WindowGroup { HarnessScreen() } }
}

private struct ImportedFixture: Identifiable {
    let id = UUID()
    let backup: MiniAppBackup
    var failReminder = false
}

private struct HarnessScreen: View {
    private let counter = CounterStore(context: MiniAppContext(id: .counter), suiteName: "jibunkit.backup-harness.data")
    private let reminder = ReminderStore(context: MiniAppContext(id: .reminder),
                                        infoDictionary: ["JibunKitAppGroup": "jibunkit.backup-harness.data"])
    @State private var fixture: ImportedFixture?
    @State private var values = ""
    @State private var ready = false

    private var definitions: [MiniAppDefinition] {
        [MiniAppDefinition(id: .counter, title: "カウンター", systemImage: "number", backup: counter.backupProvider) { _ in EmptyView() },
         MiniAppDefinition(id: .reminder, title: "リマインダー", systemImage: "bell", backup: reminder.backupProvider) { _ in EmptyView() }]
    }

    var body: some View {
        VStack {
            Text(values).accessibilityIdentifier("harness.values")
            Button("正常なバックアップ") { present(invalid: false) }.accessibilityIdentifier("harness.valid")
            Button("不正なバックアップ") { present(invalid: true) }.accessibilityIdentifier("harness.invalid")
            Button("適用時に失敗") { present(invalid: false, failReminder: true) }.accessibilityIdentifier("harness.failure")
        }
        .disabled(!ready)
        .task {
            do {
                if !ProcessInfo.processInfo.arguments.contains("--preserve") {
                    let seed = MiniAppBackupEntry(id: .counter, schemaVersion: 1, payload: Data(#"{"value":9}"#.utf8))
                    try await counter.backupProvider.prepareRestore(seed).apply()
                    try await reminder.saveMessage("keep")
                }
                await refresh()
                ready = true
            } catch { values = "Setup failed: \(error)" }
        }
        .sheet(item: $fixture, onDismiss: { Task { await refresh() } }) { item in
            BackupScreen(definitions: item.failReminder ? failingDefinitions : definitions, importedBackup: item.backup)
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
            fixture = ImportedFixture(backup: try MiniAppBackup.decode(backup.encoded()), failReminder: failReminder)
        } catch { values = "Fixture failed: \(error)" }
    }

    private func refresh() async {
        do { values = "\(try await counter.currentValue())|\(try await reminder.currentMessage())" }
        catch { values = "Read failed: \(error)" }
    }
}
