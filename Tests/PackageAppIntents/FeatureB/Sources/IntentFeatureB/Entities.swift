import AppIntents
import Foundation

// Both packages deliberately use the same Swift entity/query names and local IDs.
public struct Entry: AppEntity {
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

@MainActor
public enum EntryStore {
    private static let defaults = UserDefaults(suiteName: "com.jibunkit.intent-fixture.b")!
    public static var titles: [String: String] {
        get { defaults.dictionary(forKey: "entry-titles") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "entry-titles") }
    }
}

public struct EntryQuery: EntityStringQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [Entry] {
        let titles = EntryStore.titles
        return identifiers.compactMap { id in titles[id].map { Entry(id: id, title: $0) } }
    }

    @MainActor
    public func entities(matching string: String) async throws -> [Entry] {
        try await suggestedEntities().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [Entry] {
        EntryStore.titles.sorted { $0.key < $1.key }.map { Entry(id: $0.key, title: $0.value) }
    }
}

public struct FeatureBReadEntryIntent: AppIntent {
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
