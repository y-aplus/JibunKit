import Foundation

/// A private temporary directory owned for the lifetime of an import/export.
/// Files are immutable once the owning result has been returned to the caller.
final class BackupWorkspace: @unchecked Sendable {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("JibunKit-backup-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

/// Keep this object alive until the system file exporter finishes or cancels.
public final class MiniAppBackupFile: Sendable {
    public let url: URL
    private let workspace: BackupWorkspace

    init(url: URL, workspace: BackupWorkspace) {
        self.url = url
        self.workspace = workspace
    }
}
