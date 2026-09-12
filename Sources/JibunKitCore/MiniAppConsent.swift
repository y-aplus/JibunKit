import Foundation

/// A stable, user-facing declaration of one permission used by a Feature.
/// This describes Feature consent; it does not grant or request an OS permission.
public struct MiniAppPermissionDeclaration: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let purpose: String
    public let deniedBehavior: String

    public init(id: String, title: String, purpose: String, deniedBehavior: String) {
        self.id = id
        self.title = title
        self.purpose = purpose
        self.deniedBehavior = deniedBehavior
    }
}

public enum MiniAppConsent: String, Sendable, Equatable {
    case notDetermined
    case allowed
    case denied
}

/// Persists Feature consent by Feature and permission identifier. The caller
/// explicitly supplies the defaults domain shared by the relevant host UI.
@MainActor
public final class MiniAppConsentStore {
    public nonisolated static let defaultStorageKey = "jibunkit.feature-consents.v1"

    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults,
        storageKey: String = MiniAppConsentStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func consent(for featureID: MiniAppID, permissionID: String) -> MiniAppConsent {
        guard let rawValue = persistedValues()[key(for: featureID, permissionID: permissionID)]
        else { return .notDetermined }
        return MiniAppConsent(rawValue: rawValue) ?? .notDetermined
    }

    /// Saving `.notDetermined` removes the decision instead of persisting a
    /// synthetic answer, so a later declaration is treated as new consent.
    public func setConsent(
        _ consent: MiniAppConsent,
        for featureID: MiniAppID,
        permissionID: String
    ) {
        var values = persistedValues()
        let key = key(for: featureID, permissionID: permissionID)
        if consent == .notDetermined {
            values[key] = nil
        } else {
            values[key] = consent.rawValue
        }
        persist(values)
    }

    public func removeConsent(for featureID: MiniAppID, permissionID: String) {
        setConsent(.notDetermined, for: featureID, permissionID: permissionID)
    }

    /// Removes only decisions belonging to `featureID`. Other Features keep
    /// their decisions in the same explicitly injected defaults domain.
    public func removeConsents(for featureID: MiniAppID) {
        var values = persistedValues()
        let prefix = encoded(featureID.rawValue) + "."
        values = values.filter { !$0.key.hasPrefix(prefix) }
        persist(values)
    }

    private func persistedValues() -> [String: String] {
        defaults.dictionary(forKey: storageKey)?.compactMapValues { $0 as? String } ?? [:]
    }

    private func persist(_ values: [String: String]) {
        if values.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else {
            defaults.set(values, forKey: storageKey)
        }
    }

    private func key(for featureID: MiniAppID, permissionID: String) -> String {
        encoded(featureID.rawValue) + "." + encoded(permissionID)
    }

    private func encoded(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }
}
