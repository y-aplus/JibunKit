import Foundation

/// Pre-registration diagnostics for mini-app identifiers.
/// Complements the launch-time `precondition` checks in `MiniAppRegistry`:
/// run this from tests when adding a Feature to catch invalid or colliding
/// IDs before they reach a device.
public enum MiniAppValidationIssue: Equatable, Sendable {
    case invalidID(rawValue: String)
    case duplicateID(rawValue: String)
    case duplicateStorageNamespace(namespace: String)
    case duplicateNotificationRequestIdentifier(identifier: String)
}

public enum MiniAppValidator {
    public static func validate(ids: [MiniAppID]) -> [MiniAppValidationIssue] {
        var issues: [MiniAppValidationIssue] = []
        for id in ids where !id.isValid {
            issues.append(.invalidID(rawValue: id.rawValue))
        }
        for rawValue in duplicates(ids.map(\.rawValue)) {
            issues.append(.duplicateID(rawValue: rawValue))
        }
        for namespace in duplicates(ids.map(\.storageNamespace)) {
            issues.append(.duplicateStorageNamespace(namespace: namespace))
        }
        for identifier in duplicates(ids.map(\.notificationRequestIdentifier)) {
            issues.append(
                .duplicateNotificationRequestIdentifier(identifier: identifier)
            )
        }
        return issues
    }

    private static func duplicates(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var reported = Set<String>()
        var result: [String] = []
        for value in values {
            if !seen.insert(value).inserted, reported.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }
}
