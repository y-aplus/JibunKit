import Foundation

public enum MiniAppBackupError: Error, Equatable, Sendable {
    case unsupportedFormat
    case invalidEntry
    case duplicateID(String)
    case missingID(String)
    case unsupportedSchema(Int)
}

/// The Feature owns the payload format and its schema version.
public struct MiniAppBackupEntry: Codable, Equatable, Sendable {
    public let id: String
    public let schemaVersion: Int
    public let payload: Data

    public init(id: MiniAppID, schemaVersion: Int, payload: Data) {
        self.id = id.rawValue
        self.schemaVersion = schemaVersion
        self.payload = payload
    }
}

/// Portable envelope. Decoding does not read or modify any live Feature store.
/// Payloads are opaque bytes (base64 in JSON); they need not be JSON themselves.
public struct MiniAppBackup: Sendable {
    public let createdAt: Date
    public let entries: [MiniAppBackupEntry]

    private struct Envelope: Codable {
        let format: String
        let version: Int
        let createdAt: Date
        let entries: [MiniAppBackupEntry]
    }

    public init(entries: [MiniAppBackupEntry], createdAt: Date = .now) throws {
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw MiniAppBackupError.invalidEntry
        }
        var ids = Set<String>()
        for entry in entries {
            guard MiniAppID(entry.id).isValid, entry.schemaVersion > 0 else {
                throw MiniAppBackupError.invalidEntry
            }
            guard ids.insert(entry.id).inserted else {
                throw MiniAppBackupError.duplicateID(entry.id)
            }
        }
        self.createdAt = createdAt
        self.entries = entries
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(
            format: "JibunKitBackup", version: 1, createdAt: createdAt, entries: entries
        ))
    }

    public static func decode(_ data: Data) throws -> MiniAppBackup {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.format == "JibunKitBackup", envelope.version == 1 else {
            throw MiniAppBackupError.unsupportedFormat
        }
        return try MiniAppBackup(entries: envelope.entries, createdAt: envelope.createdAt)
    }

    /// Resolve explicitly selected Features before beginning any restoration.
    /// Unselected entries, including Features not installed here, are untouched.
    public func selecting(_ ids: Set<MiniAppID>) throws -> [MiniAppBackupEntry] {
        let available = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return try ids.sorted { $0.rawValue < $1.rawValue }.map { id in
            guard let entry = available[id.rawValue] else {
                throw MiniAppBackupError.missingID(id.rawValue)
            }
            return entry
        }
    }
}

public extension MiniAppBackupEntry {
    /// Feature code can use this convenience when its payload is Codable JSON.
    /// Decode/migrate first; only then replace the Feature's live state.
    func decodePayload<Value: Decodable>(
        _ type: Value.Type, supportedSchema: Int
    ) throws -> Value {
        guard schemaVersion == supportedSchema else {
            throw MiniAppBackupError.unsupportedSchema(schemaVersion)
        }
        return try JSONDecoder().decode(type, from: payload)
    }
}
