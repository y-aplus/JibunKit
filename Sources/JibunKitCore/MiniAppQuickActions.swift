import Foundation

/// A Home Screen quick action declared by one Feature. The host decides which
/// Features appear; the Feature decides what its own items say and open.
public struct MiniAppQuickAction: Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    /// A destination accepted by the Feature's `appendDestination`, or nil for its root.
    public let destination: String?

    public init(title: String, subtitle: String? = nil, systemImage: String, destination: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.destination = destination
    }
}

/// Most-recently-opened Feature order. It stores only IDs, never Feature data.
public struct MiniAppRecentUsage: @unchecked Sendable {
    public static let defaultStorageKey = "jibunkit.recent-features"
    public static let limit = 16

    private let defaults: UserDefaults
    private let storageKey: String

    public init(defaults: UserDefaults, storageKey: String = MiniAppRecentUsage.defaultStorageKey) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    /// Newest first. Unknown or malformed stored values are ignored.
    public var ids: [MiniAppID] {
        var seen = Set<MiniAppID>()
        return (defaults.array(forKey: storageKey) as? [String] ?? [])
            .map(MiniAppID.init(rawValue:))
            .filter { $0.isValid && seen.insert($0).inserted }
    }

    public func record(_ id: MiniAppID) {
        guard id.isValid else { return }
        save([id] + ids.filter { $0 != id })
    }

    public func remove(_ id: MiniAppID) {
        save(ids.filter { $0 != id })
    }

    private func save(_ ids: [MiniAppID]) {
        defaults.set(ids.prefix(Self.limit).map(\.rawValue), forKey: storageKey)
    }
}

/// Chooses Home Screen quick actions and resolves a selected one to a route.
public enum MiniAppQuickActions {
    public static let shortcutType = "jibunkit.quick-action"
    /// iOS shows only a few items; JibunKit never publishes more than this.
    public static let maximumCount = 4

    public struct Candidate: Sendable {
        public let id: MiniAppID
        public let title: String
        public let systemImage: String
        public let actions: [MiniAppQuickAction]

        public init(id: MiniAppID, title: String, systemImage: String, actions: [MiniAppQuickAction]) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
            self.actions = actions
        }
    }

    public struct Entry: Equatable, Sendable {
        public let id: MiniAppID
        public let action: MiniAppQuickAction
    }

    /// Recently opened Features come first, then the remaining candidates in
    /// registration order. Every Feature gets one item (its first action, or
    /// one that opens its root) before any Feature gets a second one.
    public static func entries(recent: [MiniAppID], candidates: [Candidate]) -> [Entry] {
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<MiniAppID>()
        let ordered = (recent + candidates.map(\.id)).compactMap { id -> Candidate? in
            guard let candidate = byID[id], seen.insert(id).inserted else { return nil }
            return candidate
        }
        let actions = ordered.map { candidate in
            let valid = candidate.actions.filter { action in
                action.destination.map { MiniAppLink.url(for: candidate.id, destination: $0) != nil } ?? true
            }
            return (candidate.id, valid.isEmpty
                ? [MiniAppQuickAction(title: candidate.title, systemImage: candidate.systemImage)] : valid)
        }
        var result: [Entry] = []
        var round = 0
        while result.count < maximumCount {
            let next = actions.compactMap { id, items in round < items.count ? Entry(id: id, action: items[round]) : nil }
            guard !next.isEmpty else { break }
            result += next.prefix(maximumCount - result.count)
            round += 1
        }
        return result
    }

    /// Uses the same validated keys as notification routes.
    public static func userInfo(for entry: Entry) -> [String: String] {
        var info = [MiniAppNotificationRoute.miniAppIDUserInfoKey: entry.id.rawValue]
        if let destination = entry.action.destination {
            info[MiniAppNotificationRoute.destinationUserInfoKey] = destination
        }
        return info
    }

    public static func route(type: String, userInfo: [AnyHashable: Any]?,
                             registeredIDs: Set<MiniAppID>) -> MiniAppRoute? {
        guard type == shortcutType, let userInfo,
              let route = MiniAppNotificationRoute.candidateRoute(userInfo: userInfo),
              registeredIDs.contains(route.id) else { return nil }
        return route
    }
}
