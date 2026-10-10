import Foundation
#if os(iOS)
import Observation
#endif

/// The mini apps the current Focus shows. iOS treats JibunKit as one app, so
/// its Focus settings cannot tell Features apart; the host offers one Focus
/// filter that lists them instead. While it is set, the host leaves the other
/// Features out of the list, the quick actions and the icon badge, and
/// silences their notifications. They still open from a URL or notification:
/// the filter reduces distraction and does not restrict access.
#if os(iOS)
@Observable
#endif
@MainActor
public final class MiniAppFocusSelection {
    public nonisolated static let defaultStorageKey = "jibunkit.focus-filter.shown"

    #if os(iOS)
    @ObservationIgnored
    #endif
    private let defaults: UserDefaults
    #if os(iOS)
    @ObservationIgnored
    #endif
    private let storageKey: String
    /// nil when no Focus filter applies, and every Feature is shown.
    public private(set) var shownIDs: Set<MiniAppID>?

    public init(defaults: UserDefaults, storageKey: String = MiniAppFocusSelection.defaultStorageKey) {
        self.defaults = defaults
        self.storageKey = storageKey
        shownIDs = Self.normalized(defaults.stringArray(forKey: storageKey).map { Set($0.map { MiniAppID($0) }) })
    }

    public func isShown(_ id: MiniAppID) -> Bool {
        shownIDs?.contains(id) ?? true
    }

    /// Stores the Focus filter's choice. nil or an empty choice shows every
    /// Feature, so a Focus never leaves the list empty. Returns whether it changed.
    @discardableResult
    public func apply(_ ids: Set<MiniAppID>?) -> Bool {
        let next = Self.normalized(ids)
        guard next != shownIDs else { return false }
        shownIDs = next
        if let next {
            defaults.set(next.map(\.rawValue).sorted(), forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
        return true
    }

    private static func normalized(_ ids: Set<MiniAppID>?) -> Set<MiniAppID>? {
        guard let valid = ids?.filter(\.isValid), !valid.isEmpty else { return nil }
        return valid
    }
}

public extension MiniAppContext {
    /// Set this as `UNNotificationContent.filterCriteria` (or `filter-criteria`
    /// in a remote payload) so a Focus that hides this Feature silences the
    /// notification and one that shows it lets it through.
    var notificationFilterCriteria: String { id.rawValue }
}
