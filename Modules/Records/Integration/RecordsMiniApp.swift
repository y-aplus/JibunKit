#if os(iOS)
import SwiftUI
import JibunKitCore
import RecordsFeature

@MainActor
enum RecordsMiniApp {
    static let id = MiniAppID("records")
    // A single actor owns this directory for all destinations in the host.
    private static let store: Result<RecordStore, Error> = Result {
        let files = try MiniAppFiles.shared(context: MiniAppContext(id: id))
        return try RecordStore(directory: files.directoryURL)
    }

    private static let backup: MiniAppFileBackupProvider? = {
        guard case .success(let store) = store else { return nil }
        return RecordsBackup.provider(store: store, id: id)
    }()

    static let definition = MiniAppDefinition(id: id, title: "記録", systemImage: "doc.text", fileBackup: backup,
        appendDestination: { destination, path in
            guard let recordID = UUID(uuidString: destination) else { return false }
            path.append(recordID)
            return true
        }) { _ in
        RecordsDestination(store: store)
    }
}

private struct RecordsDestination: View {
    let store: Result<RecordStore, Error>

    var body: some View {
        switch store {
        case .success(let store): RecordsRootView(store: store)
        case .failure(let error):
            ContentUnavailableView("記録の保存先を開けません", systemImage: "exclamationmark.triangle",
                                   description: Text(error.localizedDescription))
        }
    }
}
#endif
