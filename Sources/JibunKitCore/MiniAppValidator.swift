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
    case missingExpectedID(rawValue: String)
}

public enum MiniAppValidator {
    /// Pass the actual Registry IDs and the Features the integration test expects.
    /// Additional registered Features are allowed; a compiled product alone does
    /// not prove that its definition was registered in this host.
    public static func validate(
        ids: [MiniAppID], expectedIDs: Set<MiniAppID> = []
    ) -> [MiniAppValidationIssue] {
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
        let registered = Set(ids)
        for id in expectedIDs.subtracting(registered).sorted(by: { $0.rawValue < $1.rawValue }) {
            issues.append(.missingExpectedID(rawValue: id.rawValue))
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
