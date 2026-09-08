#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable
import JibunKitBackup

/// Holds the temporary ZIP until export completes; never loads it back as Data.
struct BackupArchiveDocument: Transferable {
    let file: MiniAppBackupFile

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { item in
            SentTransferredFile(item.file.url)
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
