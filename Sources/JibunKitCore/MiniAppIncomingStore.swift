import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

#if os(iOS) || os(macOS)
/// A durable handoff, not a transaction in the receiving Feature's database.
/// The receiver must make applying the stable receipt ID idempotent: a process
/// may exit after saving its value but before acknowledging the receipt.
public struct MiniAppIncomingReceipt: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let owner: String
    public let createdAt: Date
    public let items: [Item]

    public struct Item: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case text, url, file }
        public let kind: Kind
        public let typeIdentifier: String
        public let displayName: String
        /// For a file this is a generated, receipt-local filename, never a URL
        /// supplied by the sender. Text and URL items contain their string value.
        public let value: String
    }
}

public struct MiniAppIncomingDestination: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let typeIdentifiers: [String]
    // Changes when admission is republished or re-enabled. An in-flight copy
    // from before disable must not become a new receipt after re-enable.
    let admissionID: UUID

    public init(id: MiniAppID, title: String, typeIdentifiers: [String]) {
        self.id = id.rawValue
        self.title = title
        self.typeIdentifiers = typeIdentifiers
        self.admissionID = UUID()
    }

    public func accepts(_ typeIdentifier: String) -> Bool {
        typeIdentifiers.contains { declared in
            if declared == typeIdentifier { return true }
            guard let received = UTType(typeIdentifier), let accepted = UTType(declared) else { return false }
            return received.conforms(to: accepted)
        }
    }
}

public enum MiniAppIncomingError: Error, Equatable, Sendable {
    case invalidInput
    case unavailableOwner(String)
    case invalidReceipt(UUID)
    case invalidCatalog
    case notRegularFile
    case coordinationFailed
}

/// Catalog publication uses one short cross-process lock; receipt copies and
/// removal use separate per-owner locks. Large A inputs never hold B's lock.
/// No receiver, UI, or async callback runs under a file-coordination accessor.
/// The host closes admission before disabling/removing an owner. Disabling keeps
/// receipts; deleting clears that owner's receipts after admission is closed.
public struct MiniAppIncomingStore: Sendable {
    public enum Input: Sendable {
        case text(String)
        case url(URL)
        /// The caller keeps source access valid until enqueue returns.
        case file(URL, typeIdentifier: String, displayName: String)

        public var typeIdentifier: String {
            switch self {
            case .text: "public.utf8-plain-text"
            case .url: "public.url"
            case .file(_, let type, _): type
            }
        }
    }

    public struct Listing: Sendable {
        public let receipts: [MiniAppIncomingReceipt]
        /// Corruption is surfaced without hiding unrelated, valid receipts.
        public let unreadableIDs: [UUID]
    }

    private let root: URL
    private let ownersRoot: URL
    private let lockURL: URL
    private let ownerLocksRoot: URL

    public init(containerURL: URL) throws {
        guard containerURL.isFileURL else { throw MiniAppIncomingError.invalidInput }
        root = containerURL.appendingPathComponent("Library/Application Support/JibunKit/Incoming", isDirectory: true)
        ownersRoot = root.appendingPathComponent("owners", isDirectory: true)
        lockURL = root.appendingPathComponent("coordination")
        ownerLocksRoot = root.appendingPathComponent("owner-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: ownersRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ownerLocksRoot, withIntermediateDirectories: true)
    }

    public static func shared(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) throws -> Self {
        let group = try SharedGroupResolver().resolve(infoDictionary: infoDictionary)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw MiniAppFileError.unavailableGroupContainer(identifier: group)
        }
        return try Self(containerURL: container)
    }

    public func destinations() throws -> [MiniAppIncomingDestination] {
        try coordinated { try readCatalog() }
    }

    /// Replace the complete enabled destination list on normal host launch.
    /// A malformed catalog fails closed instead of silently treating it as empty.
    public func publish(_ destinations: [MiniAppIncomingDestination]) throws {
        try validate(destinations)
        try coordinated { try writeCatalog(destinations) }
    }

    public func setAdmission(_ destination: MiniAppIncomingDestination, enabled: Bool) throws {
        try validate([destination])
        try coordinated {
            var catalog = try readCatalog().filter { $0.id != destination.id }
            if enabled { catalog.append(destination) }
            try writeCatalog(catalog)
        }
    }

    public func enqueue(for owner: MiniAppID, inputs: [Input]) throws -> MiniAppIncomingReceipt {
        guard owner.isValid, !inputs.isEmpty else { throw MiniAppIncomingError.invalidInput }
        let destination = try coordinated {
            guard let destination = try readCatalog().first(where: { $0.id == owner.rawValue }) else {
                throw MiniAppIncomingError.unavailableOwner(owner.rawValue)
            }
            return destination
        }
        return try coordinated(for: owner) {
            try Task.checkCancellation()
            let id = UUID()
            let parent = try ownerDirectory(owner)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let staging = parent.appendingPathComponent(".staging-" + id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            var committed = false
            defer { if !committed { try? FileManager.default.removeItem(at: staging) } }
            var items: [MiniAppIncomingReceipt.Item] = []
            for input in inputs {
                try Task.checkCancellation()
                switch input {
                case .text(let text):
                    items.append(.init(kind: .text, typeIdentifier: "public.utf8-plain-text", displayName: "Text", value: text))
                case .url(let url):
                    guard !url.isFileURL, url.scheme != nil else { throw MiniAppIncomingError.invalidInput }
                    items.append(.init(kind: .url, typeIdentifier: "public.url", displayName: "URL", value: url.absoluteString))
                case .file(let source, let type, let name):
                    guard source.isFileURL, !type.isEmpty else { throw MiniAppIncomingError.invalidInput }
                    try requireRegularFile(source)
                    let filename = UUID().uuidString
                    try FileManager.default.copyItem(at: source, to: staging.appendingPathComponent(filename))
                    items.append(.init(kind: .file, typeIdentifier: type, displayName: name, value: filename))
                }
            }
            guard items.allSatisfy({ destination.accepts($0.typeIdentifier) }) else {
                throw MiniAppIncomingError.invalidInput
            }
            let receipt = MiniAppIncomingReceipt(id: id, owner: owner.rawValue, createdAt: .now, items: items)
            try JSONEncoder().encode(receipt).write(to: staging.appendingPathComponent("receipt.json"), options: .atomic)
            try coordinated {
                guard try readCatalog().contains(where: { $0.id == owner.rawValue && $0.admissionID == destination.admissionID }) else {
                    throw MiniAppIncomingError.unavailableOwner(owner.rawValue)
                }
                try Task.checkCancellation()
                try FileManager.default.moveItem(at: staging, to: parent.appendingPathComponent(id.uuidString, isDirectory: true))
                committed = true
            }
            return receipt
        }
    }

    public func pending(for owner: MiniAppID) throws -> Listing {
        try coordinated(for: owner) {
            let directory = try ownerDirectory(owner)
            guard FileManager.default.fileExists(atPath: directory.path) else { return Listing(receipts: [], unreadableIDs: []) }
            var entries: [MiniAppIncomingReceipt] = []
            var unreadable: [UUID] = []
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                // Enqueue holds this same cross-process lock. Thus a staging
                // directory seen here has no active writer (e.g. process exit).
                let name = url.lastPathComponent
                if name.hasPrefix(".staging-"), UUID(uuidString: String(name.dropFirst(9))) != nil {
                    try FileManager.default.removeItem(at: url)
                    continue
                }
                guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
                do { entries.append(try readReceipt(id, owner: owner)) }
                catch { unreadable.append(id) }
            }
            return Listing(receipts: entries.sorted { $0.createdAt < $1.createdAt }, unreadableIDs: unreadable)
        }
    }

    /// Includes owners no longer registered in this build so their undelivered
    /// data remains visible and can be explicitly discarded by the user.
    public func ownersWithReceipts() throws -> [MiniAppID] {
        try coordinated {
            try FileManager.default.contentsOfDirectory(at: ownersRoot, includingPropertiesForKeys: nil)
                .compactMap { url in
                    let name = url.lastPathComponent
                    let id = MiniAppID(name.replacingOccurrences(of: "%2E", with: "."))
                    // Include damaged owner entries too: the host reports each
                    // failed listing without hiding unrelated owners.
                    guard id.isValid, id.storageNamespace == name else { return nil }
                    return id
                }
        }
    }

    /// Keeps files pinned against removal while a synchronous caller copies
    /// them into its own staging area. Do not call another store method inside.
    public func withReceipt<Value>(id: UUID, owner: MiniAppID,
        operation: (MiniAppIncomingReceipt, URL) throws -> Value) throws -> Value {
        try coordinated(for: owner) {
            let receipt = try readReceipt(id, owner: owner)
            return try operation(receipt, ownerDirectory(owner).appendingPathComponent(id.uuidString, isDirectory: true))
        }
    }

    public func acknowledge(id: UUID, owner: MiniAppID) throws {
        try coordinated(for: owner) {
            _ = try readReceipt(id, owner: owner)
            try FileManager.default.removeItem(at: ownerDirectory(owner).appendingPathComponent(id.uuidString, isDirectory: true))
        }
    }

    /// Explicit discard also permits removing a corrupt receipt without decoding
    /// it. UUID and owner generate the path; untrusted JSON never selects it.
    public func discard(id: UUID, owner: MiniAppID) throws {
        try coordinated(for: owner) {
            let path = try ownerDirectory(owner).appendingPathComponent(id.uuidString, isDirectory: true)
            if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
        }
    }

    public func removeOwnedData(for owner: MiniAppID) throws {
        try coordinated(for: owner) {
            try coordinated {
                guard try !readCatalog().contains(where: { $0.id == owner.rawValue }) else {
                    throw MiniAppIncomingError.invalidInput
                }
            }
            let directory = try ownerDirectory(owner)
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        }
    }

    private func ownerDirectory(_ owner: MiniAppID) throws -> URL {
        guard owner.isValid else { throw MiniAppIncomingError.invalidInput }
        let directory = ownersRoot.appendingPathComponent(owner.storageNamespace, isDirectory: true)
        let resolvedRoot = ownersRoot.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard directory.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(resolvedRoot) else {
            throw MiniAppIncomingError.invalidInput
        }
        if FileManager.default.fileExists(atPath: directory.path),
           try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw MiniAppIncomingError.invalidInput
        }
        return directory
    }

    private func readReceipt(_ id: UUID, owner: MiniAppID) throws -> MiniAppIncomingReceipt {
        let directory = try ownerDirectory(owner).appendingPathComponent(id.uuidString, isDirectory: true)
        let attributes = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard attributes.isDirectory == true, attributes.isSymbolicLink != true else { throw MiniAppIncomingError.invalidReceipt(id) }
        let metadata = directory.appendingPathComponent("receipt.json")
        try requireRegularFile(metadata)
        let result = try JSONDecoder().decode(MiniAppIncomingReceipt.self, from: Data(contentsOf: metadata))
        guard result.id == id, result.owner == owner.rawValue, !result.items.isEmpty else { throw MiniAppIncomingError.invalidReceipt(id) }
        for item in result.items where item.kind == .file {
            guard let fileID = UUID(uuidString: item.value), fileID.uuidString == item.value else { throw MiniAppIncomingError.invalidReceipt(id) }
            try requireRegularFile(directory.appendingPathComponent(item.value))
        }
        return result
    }

    private func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw MiniAppIncomingError.notRegularFile }
    }

    private func readCatalog() throws -> [MiniAppIncomingDestination] {
        let file = root.appendingPathComponent("destinations.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        try requireRegularFile(file)
        let result = try JSONDecoder().decode([MiniAppIncomingDestination].self, from: Data(contentsOf: file))
        try validate(result)
        return result
    }

    private func validate(_ catalog: [MiniAppIncomingDestination]) throws {
        guard Set(catalog.map(\.id)).count == catalog.count,
              catalog.allSatisfy({ MiniAppID($0.id).isValid && !$0.title.isEmpty && !$0.typeIdentifiers.isEmpty && $0.typeIdentifiers.allSatisfy { !$0.isEmpty } })
        else { throw MiniAppIncomingError.invalidCatalog }
    }

    private func writeCatalog(_ catalog: [MiniAppIncomingDestination]) throws {
        try JSONEncoder().encode(catalog).write(to: root.appendingPathComponent("destinations.json"), options: .atomic)
    }

    private func coordinated<Value>(_ operation: () throws -> Value) throws -> Value {
        try coordinate(at: lockURL, operation)
    }

    private func coordinated<Value>(for owner: MiniAppID, _ operation: () throws -> Value) throws -> Value {
        guard owner.isValid else { throw MiniAppIncomingError.invalidInput }
        return try coordinate(at: ownerLocksRoot.appendingPathComponent(owner.storageNamespace), operation)
    }

    private func coordinate<Value>(at url: URL, _ operation: () throws -> Value) throws -> Value {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Value, Error>?
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { _ in
            result = Result { try operation() }
        }
        if let result { return try result.get() }
        throw coordinationError ?? MiniAppIncomingError.coordinationFailed as NSError
    }
}
#endif
