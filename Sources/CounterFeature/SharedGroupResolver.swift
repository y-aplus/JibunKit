import Foundation

public enum SharedGroupResolutionError: Error, Equatable, Sendable {
    case missingLogicalIdentifier
    case invalidSignedGroups
    case noMatchingSignedGroup(logicalIdentifier: String)
    case multipleMatchingSignedGroups(logicalIdentifier: String, matches: [String])
    case unavailableUserDefaultsSuite(identifier: String)
}

public struct SharedGroupResolver: Sendable {
    public static let logicalGroupInfoKey = "AppbaseAppGroup"
    public static let signedGroupsInfoKey = "ALTAppGroups"

    public init() {}

    public func resolve(infoDictionary: [String: Any]) throws -> String {
        guard
            let logicalIdentifier = infoDictionary[Self.logicalGroupInfoKey] as? String,
            !logicalIdentifier.isEmpty
        else {
            throw SharedGroupResolutionError.missingLogicalIdentifier
        }

        guard let signedGroupsValue = infoDictionary[Self.signedGroupsInfoKey] else {
            return logicalIdentifier
        }
        guard let signedGroups = signedGroupsValue as? [String] else {
            throw SharedGroupResolutionError.invalidSignedGroups
        }

        let matches = signedGroups
            .filter { $0.hasSuffix(logicalIdentifier) }
            .sorted()

        switch matches.count {
        case 1:
            return matches[0]
        case 0:
            throw SharedGroupResolutionError.noMatchingSignedGroup(
                logicalIdentifier: logicalIdentifier
            )
        default:
            throw SharedGroupResolutionError.multipleMatchingSignedGroups(
                logicalIdentifier: logicalIdentifier,
                matches: matches
            )
        }
    }
}
