import Foundation

/// Temporary, owner-scoped copies for APIs that may move notification media.
/// Does not schedule requests or replace UserNotifications' native content API.
public struct MiniAppNotificationAttachments: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case invalidContainer
        case notRegularFile(URL)
    }

    public let directoryURL: URL

    /// The container is app-owned; it can also be an isolated standalone container.
    public init(context: MiniAppContext, containerURL: URL) throws {
        guard containerURL.isFileURL else { throw Failure.invalidContainer }
        directoryURL = containerURL
            .appendingPathComponent("Library/Caches/JibunKit/NotificationAttachments", isDirectory: true)
            .appendingPathComponent(context.id.storageNamespace, isDirectory: true)
    }

    /// Build native attachments from these copies and await the native add call
    /// inside `operation`. Never return while a callback still uses the copies.
    /// The Feature must retain its normal lifetime/store reservation throughout.
    /// Native success is not turned into cancellation after it has committed.
    @MainActor
    public func withFiles<Value>(
        copiedFrom sources: [URL],
        operation: @MainActor ([URL]) async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let directory = directoryURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let preparation = Task.detached { try Self.copy(sources, into: directory) }
        let files = try await withTaskCancellationHandler {
            try await preparation.value
        } onCancel: { preparation.cancel() }
        // The copy task has actually finished before cleanup can touch its files.
        // OS-owned attachment URLs are never removed here. A failed cache cleanup
        // may leave this UUID directory for removeStagingFiles after owner shutdown.
        defer { try? FileManager.default.removeItem(at: directory) }
        try Task.checkCancellation()
        return try await operation(files)
    }

    /// After this owner's writers have drained, remove abandoned preparation
    /// copies (including ones left by process termination), never OS attachments.
    /// Pending/delivered requests must be removed through UNUserNotificationCenter.
    public func removeStagingFiles() throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try FileManager.default.removeItem(at: directoryURL)
    }

    private static func copy(_ sources: [URL], into directory: URL) throws -> [URL] {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var files: [URL] = []
            for (index, source) in sources.enumerated() {
                try Task.checkCancellation()
                guard source.isFileURL else { throw Failure.notRegularFile(source) }
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw Failure.notRegularFile(source)
                }
                let target = directory.appendingPathComponent("\(index)-\(source.lastPathComponent)")
                try FileManager.default.copyItem(at: source, to: target)
                files.append(target)
            }
            try Task.checkCancellation()
            return files
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
