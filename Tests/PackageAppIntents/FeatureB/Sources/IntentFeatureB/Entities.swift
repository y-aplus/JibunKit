import AppIntents
import Foundation

// Both packages deliberately use the same Swift entity/query names and local IDs.
public struct Entry: AppEntity {
    public static let persistentIdentifier = "com.jibunkit.intent-fixture.b.entry"
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Feature B entry"
    public static let defaultQuery = EntryQuery()
    public let id: String
    @Property(title: "Title") public var title: String
    public var displayRepresentation: DisplayRepresentation { .init(title: "\(title)") }

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct EntryQuery: EntityStringQuery {
    public static let persistentIdentifier = "com.jibunkit.intent-fixture.b.entry-query"
    public init() {}

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [Entry] {
        let titles = try await FeatureBStore.shared.entries()
        return identifiers.compactMap { id in titles[id].map { Entry(id: id, title: $0) } }
    }

    @MainActor
    public func entities(matching string: String) async throws -> [Entry] {
        try await suggestedEntities().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [Entry] {
        try await FeatureBStore.shared.entries().sorted { $0.key < $1.key }
            .map { Entry(id: $0.key, title: $0.value) }
    }
}

public struct ReadEntryIntent: AppIntent {
    // Preserve the previously extracted public identity while the Swift name changes.
    public static let persistentIdentifier = "FeatureBReadEntryIntent"
    public static let title: LocalizedStringResource = "Read Feature B entry"
    public static var supportedModes: IntentModes { [.background] }
    @Parameter(title: "Entry") public var entry: Entry
    public init() {}
    public init(entry: Entry) { self.entry = entry }

    public enum Failure: Error { case missingEntry }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let current = try await EntryQuery().entities(for: [entry.id]).first else {
            throw Failure.missingEntry
        }
        return .result(value: current.title)
    }
}
