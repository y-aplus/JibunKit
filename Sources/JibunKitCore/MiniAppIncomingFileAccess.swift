import Foundation

#if os(iOS) || os(macOS)
public enum MiniAppIncomingFileAccess {
    /// Use inside a provider's file-representation completion callback, or while
    /// handling an external file URL. Copies while access is valid; neither the
    /// security scope nor the provider's temporary URL escapes the operation.
    /// Run file I/O away from the main actor. Destination must be caller-owned.
    public static func copy(from source: URL, to destination: URL) throws {
        try copy(from: source, to: destination,
                 start: { $0.startAccessingSecurityScopedResource() },
                 stop: { $0.stopAccessingSecurityScopedResource() })
    }

    static func copy(from source: URL, to destination: URL,
                     start: (URL) -> Bool, stop: (URL) -> Void) throws {
        guard source.isFileURL, destination.isFileURL else { throw MiniAppIncomingError.invalidInput }
        let accessed = start(source)
        defer { if accessed { stop(source) } }
        try Task.checkCancellation()
        var error: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: [], error: &error) { readable in
            result = Result {
                let values = try readable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw MiniAppIncomingError.notRegularFile }
                try FileManager.default.copyItem(at: readable, to: destination)
                do { try Task.checkCancellation() }
                catch {
                    try? FileManager.default.removeItem(at: destination)
                    throw error
                }
            }
        }
        if let result { return try result.get() }
        throw error ?? MiniAppIncomingError.coordinationFailed as NSError
    }
}
#endif
