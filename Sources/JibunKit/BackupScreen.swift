#if os(iOS)
import JibunKitCore
import JibunKitBackup
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct BackupScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exportIDs: Set<MiniAppID> = []
    @State private var restoreIDs: Set<MiniAppID> = []
    @State private var imported: ImportedMiniAppBackup?
    @State private var archive: BackupArchiveDocument?
    @State private var exportingArchive = false
    @State private var document: BackupDocument?
    @State private var exportFilename = "JibunKit-backup"
    @State private var importing = false
    @State private var exporting = false
    @State private var confirming = false
    @State private var pending: MiniAppRestorePlan?
    @State private var busy = false
    @State private var status: String?

    private let definitions: [MiniAppDefinition]
    private let lifecycleForDefinition: @MainActor (MiniAppDefinition) -> MiniAppRestoreLifecycle?

    init(definitions: [MiniAppDefinition], importedBackup: MiniAppBackup? = nil, importedArchive: ImportedMiniAppBackup? = nil,
         lifecycleForDefinition: @escaping @MainActor (MiniAppDefinition) -> MiniAppRestoreLifecycle? = { $0.effectiveRestoreLifecycle }) {
        self.definitions = definitions
        self.lifecycleForDefinition = lifecycleForDefinition
        _imported = State(initialValue: importedArchive ?? importedBackup.map { ImportedMiniAppBackup(legacy: $0) })
    }
    private var providers: [MiniAppBackupProvider] { definitions.compactMap(\.backup) }
    private var fileProviders: [MiniAppFileBackupProvider] { definitions.compactMap(\.fileBackup) }

    var body: some View {
        NavigationStack {
            Form {
                exportSection
                restoreSection

                if busy { ProgressView("Working…") }
                if let status { Section { Text(status).accessibilityIdentifier("backup.status") } }
            }
            .disabled(busy)
            .navigationTitle("Backup and Restore")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }.disabled(busy)
                }
            }
            .interactiveDismissDisabled(busy)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .zip]) { result in
                #if DEBUG
                Self.importLogger.info("completion entered")
                #endif
                switch result {
                case .success(let url):
                    #if DEBUG
                    Self.importLogger.info("completion success extension=\(url.pathExtension, privacy: .public)")
                    #endif
                    load(url)
                case .failure(let error):
                    #if DEBUG
                    Self.importLogger.error("completion failure type=\(String(reflecting: type(of: error)), privacy: .public)")
                    #endif
                    status = String(localized: "Couldn’t read the file. Saved data was not changed.")
                }
            }
            .onChange(of: importing) { _, presented in
                #if DEBUG
                Self.importLogger.info("presentation changed presented=\(presented, privacy: .public)")
                #endif
            }
            .background {
                Color.clear.fileExporter(isPresented: $exporting, document: document, contentType: .json,
                          defaultFilename: exportFilename, onCompletion: exportCompleted)
            }
            .onChange(of: exporting) { _, presented in
                if !presented { document = nil }
            }
            .background {
                Color.clear.fileExporter(isPresented: $exportingArchive, item: archive, contentTypes: [.zip],
                          defaultFilename: exportFilename, onCompletion: exportCompleted,
                          onCancellation: { archive = nil })
            }
            .alert("Replace the current data?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) { pending = nil }
                Button("Replace and Restore", role: .destructive) { restore() }
            } message: {
                Text("\(names(pending?.ids ?? [])) will be returned to the backup’s contents. If restoring fails partway, only part of the data may be restored.")
            }
        }
    }

    private var exportSection: some View {
        Section {
            ForEach(definitions) { definition in
                if definition.backup != nil || definition.fileBackup != nil {
                    Toggle(definition.title, isOn: selection(definition.id, in: $exportIDs))
                        .accessibilityIdentifier("backup.export.\(definition.id.rawValue)")
                } else {
                    LabeledContent(definition.title, value: String(localized: "Backup not supported"))
                }
            }
            Button("Export Selected Apps") { exportSelected() }
                .disabled(exportIDs.isEmpty)
                .accessibilityIdentifier("backup.export")
        } header: { Text("Backup") }
        footer: { Text("Saves the selected apps’ data to a file. The file isn’t encrypted.") }
    }

    private var restoreSection: some View {
        Section {
            Button("Load Backup") {
                imported = nil
                restoreIDs = []
                pending = nil
                status = nil
                #if DEBUG
                Self.importLogger.info("presentation requested types=json,zip")
                #endif
                importing = true
            }
            .accessibilityIdentifier("backup.import")
            if let imported {
                LabeledContent("Created", value: imported.createdAt.formatted(date: .abbreviated, time: .shortened))
                ForEach(imported.entries, id: \.id) { entry in
                    restoreRow(entry)
                }
                Button("Restore Selected Apps") { prepareRestore(imported) }
                    .disabled(restoreIDs.isEmpty)
                    .accessibilityIdentifier("backup.restore")
            }
        } header: { Text("Restore") }
        footer: { Text("Replaces the current data of the selected apps. Apps you don’t select aren’t changed.") }
    }

    @ViewBuilder
    private func restoreRow(_ entry: ImportedMiniAppBackup.Entry) -> some View {
        if let definition = restoreDefinition(for: entry) {
            Toggle(definition.title, isOn: selection(entry.id, in: $restoreIDs))
                .accessibilityIdentifier("backup.restore.\(entry.id.rawValue)")
        } else {
            LabeledContent(title(entry.id), value: String(localized: "Can’t be restored in this configuration"))
        }
    }

    private func restoreDefinition(for entry: ImportedMiniAppBackup.Entry) -> MiniAppDefinition? {
        guard let definition = definitions.first(where: { $0.id == entry.id }) else { return nil }
        switch entry.storage {
        case .payload: return definition.backup == nil ? nil : definition
        case .files: return definition.fileBackup == nil ? nil : definition
        }
    }

    private func exportCompleted(_ result: Result<URL, Error>) {
        switch result {
        case .success: status = String(localized: "Backup exported.")
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError { status = String(localized: "Couldn’t export.") }
        }
        document = nil
        archive = nil
    }

    private func title(_ id: MiniAppID) -> String {
        definitions.first { $0.id == id }?.title ?? id.rawValue
    }

    private func names(_ ids: some Sequence<MiniAppID>) -> String {
        ids.map(title).formatted(.list(type: .and))
    }

    private func selection(_ id: MiniAppID, in values: Binding<Set<MiniAppID>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(id) }, set: { selected in
            if selected { values.wrappedValue.insert(id) } else { values.wrappedValue.remove(id) }
        })
    }

    private func exportSelected() {
        let ids = exportIDs
        let selected = providers.filter { ids.contains($0.id) }
        let selectedFiles = fileProviders.filter { ids.contains($0.id) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        exportFilename = "JibunKit-backup-\(formatter.string(from: Date()))"
        let archiveFilename = exportFilename + ".zip"
        busy = true
        status = nil
        Task {
            defer { busy = false }
            do {
                if selectedFiles.isEmpty {
                    let data = try await Task.detached {
                        var entries: [MiniAppBackupEntry] = []
                        for provider in selected { entries.append(try await provider.exportEntry()) }
                        return try MiniAppBackup(entries: entries).encoded()
                    }.value
                    document = BackupDocument(data: data)
                    exporting = true
                } else {
                    let file = try await Task.detached {
                        try await MiniAppBackupArchive.export(selected: ids, providers: selected, fileProviders: selectedFiles,
                                                              filename: archiveFilename)
                    }.value
                    archive = BackupArchiveDocument(file: file)
                    exportingArchive = true
                }
            } catch is MiniAppRestoreCoordinator.Conflict {
                status = String(localized: "The selected apps are using their data. Try again when they finish. No file was exported.")
            } catch { status = String(localized: "Couldn’t create the backup. No file was exported.") }
        }
    }

    private func load(_ url: URL) {
        #if DEBUG
        Self.importLogger.info("load begin extension=\(url.pathExtension, privacy: .public)")
        #endif
        busy = true
        Task {
            defer { busy = false }
            do {
                imported = try await Task.detached {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try MiniAppBackupArchive.load(from: url)
                }.value
                #if DEBUG
                Self.importLogger.info("load success entries=\(imported?.entries.count ?? 0, privacy: .public)")
                #endif
                status = String(localized: "Choose the apps to restore. Saved data hasn’t been changed yet.")
            } catch {
                #if DEBUG
                Self.importLogger.error("load failure type=\(String(reflecting: type(of: error)), privacy: .public)")
                #endif
                status = String(localized: "Couldn’t read a supported backup. Saved data was not changed.")
            }
        }
    }

    #if DEBUG
    private static let importLogger = Logger(subsystem: "com.jibunkit.app", category: "BackupImport")
    #endif

    private func prepareRestore(_ backup: ImportedMiniAppBackup) {
        let selected = restoreIDs
        let available = providers
        let availableFiles = fileProviders
        busy = true
        status = nil
        Task {
            defer { busy = false }
            do {
                pending = try await Task.detached {
                    try backup.prepareRestore(selected: selected, providers: available, fileProviders: availableFiles)
                }.value
                confirming = true
            } catch { status = String(localized: "Can’t restore the selected data. Check its contents and version. Saved data was not changed.") }
        }
    }

    private func restore() {
        guard let plan = pending else { return }
        pending = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                let lifecycles = Dictionary(uniqueKeysWithValues: definitions.compactMap { definition in
                    lifecycleForDefinition(definition).map { (definition.id, $0) }
                })
                try await plan.apply(lifecycles: lifecycles)
                status = String(localized: "Restored \(names(plan.ids)).")
                imported = nil
                restoreIDs = []
            } catch is CancellationError {
                status = String(localized: "Stopped before restoring began. Saved data was not changed.")
            } catch let error as MiniAppRestoreCoordinator.Conflict {
                let busy = names(error.owners.sorted { $0.rawValue < $1.rawValue })
                status = String(localized: "\(busy) are using their data. Choose again when they finish. This restore didn’t change saved data.")
            } catch let error as MiniAppRestoreFailure {
                let completed = error.completed.isEmpty ? String(localized: "None") : names(error.completed)
                let detail: String
                switch error.stage {
                case .cancelledBeforeStart:
                    detail = String(localized: "Stopped before restoring this app. Its saved data was not changed.")
                case .stop:
                    detail = String(localized: "Its running work couldn’t be stopped, so its saved data was not restored.")
                case .stopAndRecovery:
                    detail = String(localized: "Saved data was not restored. Stopping this app failed, and it couldn’t be returned to a usable state.")
                case .apply:
                    detail = String(localized: "Restoring saved data failed. Some of it may have changed.")
                case .resume:
                    detail = String(localized: "Saved data was restored, but resuming this app failed.")
                case .applyAndResume:
                    detail = String(localized: "Restoring saved data and resuming this app both failed. Some data may have changed.")
                }
                let failed = title(error.failed)
                status = String(localized: "Restore stopped. Completed: \(completed). \(failed): \(detail) Check this app’s state. Later apps were not changed.")
            } catch { status = String(localized: "Restore failed. Check the apps’ state.") }
        }
    }
}
#endif
