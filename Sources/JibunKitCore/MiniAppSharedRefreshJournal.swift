import Foundation

struct MiniAppSharedRefreshRecord: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case pending
        case running
        case recovery
    }

    let owner: String
    let identifier: String
    let generation: UUID
    let earliestBeginDate: Date?
    var phase: Phase
}

@MainActor
protocol MiniAppSharedRefreshJournaling {
    func load() throws -> [MiniAppSharedRefreshRecord]
    func save(_ records: [MiniAppSharedRefreshRecord]) throws
}

enum MiniAppSharedRefreshJournalError: Error, Equatable {
    case invalidURL
    case unsupportedVersion(Int)
    case invalidRecord
}

@MainActor
final class FileSharedRefreshJournal: MiniAppSharedRefreshJournaling {
    private struct Envelope: Codable {
        let version: Int
        let records: [MiniAppSharedRefreshRecord]
    }

    private static let currentVersion = 1
    private let url: URL

    init(url: URL) throws {
        guard url.isFileURL else {
            throw MiniAppSharedRefreshJournalError.invalidURL
        }
        self.url = url
    }

    func load() throws -> [MiniAppSharedRefreshRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == Self.currentVersion else {
            throw MiniAppSharedRefreshJournalError.unsupportedVersion(envelope.version)
        }
        try Self.validate(envelope.records)
        return envelope.records
    }

    func save(_ records: [MiniAppSharedRefreshRecord]) throws {
        try Self.validate(records)
        let data = try JSONEncoder().encode(Envelope(
            version: Self.currentVersion,
            records: records
        ))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func validate(_ records: [MiniAppSharedRefreshRecord]) throws {
        var generations: Set<UUID> = []
        var pendingKeys: Set<OwnerIdentifier> = []
        for record in records {
            guard !record.owner.isEmpty,
                  !record.identifier.isEmpty,
                  record.earliestBeginDate?.timeIntervalSinceReferenceDate.isFinite != false,
                  generations.insert(record.generation).inserted
            else {
                throw MiniAppSharedRefreshJournalError.invalidRecord
            }
            if record.phase == .pending {
                guard pendingKeys.insert(OwnerIdentifier(
                    owner: record.owner,
                    identifier: record.identifier
                )).inserted else {
                    throw MiniAppSharedRefreshJournalError.invalidRecord
                }
            }
        }
    }

    private struct OwnerIdentifier: Hashable {
        let owner: String
        let identifier: String
    }
}
