import Foundation

public enum MiniAppFileError: Error, Equatable, Sendable {
    case unavailableGroupContainer(identifier: String)
    case invalidFileName(String)
    case invalidContainerURL
}

/// Feature-owned files, independent of their encoding or database engine.
/// This is namespace organization, not a security sandbox between Features.
public struct MiniAppFiles: Sendable {
    public let directoryURL: URL

    /// An explicit container also supports standalone apps and isolated tests.
    /// The caller owns this directory and its lifecycle.
    public init(context: MiniAppContext, containerURL: URL) throws {
        guard containerURL.isFileURL else { throw MiniAppFileError.invalidContainerURL }
        directoryURL = containerURL
            .appendingPathComponent("Library/Application Support/JibunKit/Features", isDirectory: true)
            .appendingPathComponent(context.id.storageNamespace, isDirectory: true)
    }

    #if os(iOS) || os(macOS)
    public static func shared(
        context: MiniAppContext,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) throws -> MiniAppFiles {
        try shared(context: context, infoDictionary: infoDictionary) {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }
    }
    #endif

    static func shared(
        context: MiniAppContext,
        infoDictionary: [String: Any],
        resolveContainer: (String) -> URL?
    ) throws -> MiniAppFiles {
        let identifier = try SharedGroupResolver().resolve(infoDictionary: infoDictionary)
        guard let container = resolveContainer(identifier) else {
            throw MiniAppFileError.unavailableGroupContainer(identifier: identifier)
        }
        return try MiniAppFiles(context: context, containerURL: container)
    }

    /// Does not create directories. Use prepareDirectory before opening a database.
    public func fileURL(named name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw MiniAppFileError.invalidFileName(name) }
        return directoryURL.appendingPathComponent(name, isDirectory: false)
    }

    public func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    /// Missing files and permission/corruption errors remain distinguishable errors.
    public func read(named name: String) throws -> Data {
        try Data(contentsOf: fileURL(named: name))
    }

    /// Replaces one complete file atomically. This is not a read-modify-write
    /// transaction or database backup; concurrent writers need coordination.
    public func write(_ data: Data, named name: String) throws {
        let destination = try fileURL(named: name)
        try prepareDirectory()
        try data.write(to: destination, options: .atomic)
    }
}
