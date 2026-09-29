#if canImport(CoreSpotlight)
import CoreSpotlight
import Foundation

/// Namespaces Core Spotlight items for one Feature inside the host's index.
/// This is cooperative ownership, not a security boundary inside the host process.
public struct MiniAppSpotlightNamespace: Sendable {
    public let domainIdentifier: String

    public init(context: MiniAppContext) {
        domainIdentifier = "jibunkit.\(context.id.storageNamespace).spotlight"
    }

    public func itemIdentifier(for localIdentifier: String) -> String {
        domainIdentifier + "." + Data(localIdentifier.utf8).base64EncodedString()
    }

    public func owns(itemIdentifier: String) -> Bool {
        itemIdentifier.hasPrefix(domainIdentifier + ".")
    }

    /// Decode only this namespace's canonical identifiers, preserving the opaque
    /// local ID for the owning Feature to validate against its current content.
    public func localIdentifier(for itemIdentifier: String) -> String? {
        guard owns(itemIdentifier: itemIdentifier) else { return nil }
        let encoded = String(itemIdentifier.dropFirst(domainIdentifier.count + 1))
        guard let data = Data(base64Encoded: encoded), data.base64EncodedString() == encoded,
              let localIdentifier = String(data: data, encoding: .utf8) else { return nil }
        return localIdentifier
    }

    /// Preserves the complete native attribute set while assigning owned identifiers.
    public func searchableItem(
        localIdentifier: String,
        attributes: CSSearchableItemAttributeSet
    ) -> CSSearchableItem {
        // CSSearchableItem writes identifier/domain fields into its attribute set.
        // Copy the complete native object so reuse across owners cannot alias them.
        let ownedAttributes = attributes.copy() as! CSSearchableItemAttributeSet
        return CSSearchableItem(
            uniqueIdentifier: itemIdentifier(for: localIdentifier),
            domainIdentifier: domainIdentifier,
            attributeSet: ownedAttributes
        )
    }

    public func index(
        localIdentifier: String,
        attributes: CSSearchableItemAttributeSet,
        in index: CSSearchableIndex
    ) async throws {
        try await index.indexSearchableItems([
            searchableItem(localIdentifier: localIdentifier, attributes: attributes)
        ])
    }

    public func delete(localIdentifier: String, from index: CSSearchableIndex) async throws {
        try await index.deleteSearchableItems(withIdentifiers: [
            itemIdentifier(for: localIdentifier)
        ])
    }

    /// Deletes every item in this Feature's domain, never the host's entire index.
    public func deleteAll(from index: CSSearchableIndex) async throws {
        try await index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier])
    }
}

/// Resolves a native selected-item activity into an existing Feature address.
/// Search-query continuation and arbitrary NSUserActivity payloads are separate.
public enum MiniAppSpotlightRoute {
    public static func resolve(_ activity: NSUserActivity, registeredIDs: Set<MiniAppID>) -> MiniAppRoute? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        for id in registeredIDs where id.isValid {
            let namespace = MiniAppSpotlightNamespace(context: MiniAppContext(id: id))
            if let localIdentifier = namespace.localIdentifier(for: identifier) {
                return MiniAppRoute(id: id, destination: localIdentifier)
            }
        }
        return nil
    }
}

/// Resolves Spotlight's "Search in App" query into Feature-owned destinations.
/// A Feature opts in by mapping the query to one of its own destination
/// identifiers; the host never interprets the query or the destination.
public enum MiniAppSearchContinuation {
    public struct Registration {
        public let id: MiniAppID
        public let destination: @MainActor (String) -> String?

        public init(id: MiniAppID, destination: @escaping @MainActor (String) -> String?) {
            self.id = id
            self.destination = destination
        }
    }

    /// The trimmed query of a native continuation activity, or nil for any
    /// other activity type, a missing or non-string value, or an empty query.
    public static func query(from activity: NSUserActivity) -> String? {
        guard activity.activityType == CSQueryContinuationActionType,
              let raw = activity.userInfo?[CSSearchQueryString] as? String else { return nil }
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
    }

    /// Routes for the registered Features that accept this query, in
    /// registration order. A Feature declines by returning nil.
    @MainActor
    public static func candidates(for query: String, registrations: [Registration],
                                  registeredIDs: Set<MiniAppID>) -> [MiniAppRoute] {
        registrations.compactMap { registration in
            guard registeredIDs.contains(registration.id),
                  let destination = registration.destination(query),
                  MiniAppLink.url(for: registration.id, destination: destination) != nil else { return nil }
            return MiniAppRoute(id: registration.id, destination: destination)
        }
    }
}
#endif
