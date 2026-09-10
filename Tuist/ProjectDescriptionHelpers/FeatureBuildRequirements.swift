import Foundation
import ProjectDescription

/// Build-time requirements for one Feature in one native target. This does not
/// request OS permission or promise that the chosen signing identity supports it.
public struct FeatureBuildRequirement: Sendable {
    public let owner: String
    public let infoPlist: [String: Plist.Value]
    public let entitlements: [String: Plist.Value]

    public init(owner: String, infoPlist: [String: Plist.Value] = [:],
                entitlements: [String: Plist.Value] = [:]) {
        self.owner = owner
        self.infoPlist = infoPlist
        self.entitlements = entitlements
    }
}

public struct ComposedFeatureBuild: Sendable {
    public let infoPlist: [String: Plist.Value]
    public let entitlements: [String: Plist.Value]
}

public struct FeatureBuildConfiguration: Sendable {
    public let features: [FeatureBuildRequirement]
    public let infoPlistResolutions: [String: Plist.Value]
    public let entitlementResolutions: [String: Plist.Value]

    public init(features: [FeatureBuildRequirement] = [],
                infoPlistResolutions: [String: Plist.Value] = [:],
                entitlementResolutions: [String: Plist.Value] = [:]) {
        self.features = features
        self.infoPlistResolutions = infoPlistResolutions
        self.entitlementResolutions = entitlementResolutions
    }

    public func compose(infoPlist: [String: Plist.Value],
                        entitlements: [String: Plist.Value]) throws -> ComposedFeatureBuild {
        var owners: Set<String> = ["host"]
        for feature in features {
            guard !feature.owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  owners.insert(feature.owner).inserted else {
                throw Failure("Feature build owner must be nonempty and unique: \(feature.owner)")
            }
            for key in ["CFBundleIdentifier", "CFBundleExecutable"] where feature.infoPlist[key] != nil {
                throw Failure("\(feature.owner) requests host identity key \(key); configure the native target instead")
            }
        }
        return try ComposedFeatureBuild(
            infoPlist: merge(kind: "Info.plist", host: infoPlist,
                contributions: features.map { ($0.owner, $0.infoPlist) },
                resolutions: infoPlistResolutions,
                stringSetKeys: ["UIBackgroundModes", "BGTaskSchedulerPermittedIdentifiers", "LSApplicationQueriesSchemes"]),
            entitlements: merge(kind: "entitlements", host: entitlements,
                contributions: features.map { ($0.owner, $0.entitlements) },
                resolutions: entitlementResolutions,
                stringSetKeys: ["com.apple.security.application-groups", "keychain-access-groups", "com.apple.developer.associated-domains"])
        )
    }

    public struct Failure: Error, LocalizedError {
        public let message: String
        init(_ message: String) { self.message = message }
        public var errorDescription: String? { message }
    }

    private func merge(kind: String, host: [String: Plist.Value],
                       contributions: [(String, [String: Plist.Value])],
                       resolutions: [String: Plist.Value], stringSetKeys: Set<String>) throws -> [String: Plist.Value] {
        let sources = [("host", host)] + contributions
        let requestedKeys = Set(sources.flatMap { $0.1.keys })
        for key in resolutions.keys.sorted() where !requestedKeys.contains(key) {
            throw Failure("Unused \(kind) resolution for \(key); add host settings to the native target")
        }
        var result: [String: Plist.Value] = [:]
        for key in requestedKeys.sorted() {
            let requests = sources.compactMap { owner, values in values[key].map { (owner, $0) } }
            if stringSetKeys.contains(key) {
                var strings = Set<String>()
                let effectiveRequests = resolutions[key].map { [("resolution", $0)] } ?? requests
                for (owner, value) in effectiveRequests {
                    guard case let .array(values) = value else {
                        throw Failure("\(owner) must supply a string array for \(kind) key \(key)")
                    }
                    for value in values {
                        guard case let .string(string) = value else {
                            throw Failure("\(owner) must supply a string array for \(kind) key \(key)")
                        }
                        strings.insert(string)
                    }
                }
                result[key] = .array(strings.sorted().map { .string($0) })
            } else if let resolution = resolutions[key] {
                result[key] = resolution
            } else if let first = requests.first?.1, requests.allSatisfy({ $0.1 == first }) {
                result[key] = first
            } else {
                let owners = requests.map(\.0).joined(separator: ", ")
                throw Failure("Conflicting \(kind) key \(key) requested by \(owners); add an explicit resolution")
            }
        }
        return result
    }
}
