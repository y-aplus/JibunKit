import Foundation
import ProjectDescription

/// Build-time requirements for one Feature in one native target. This does not
/// request OS permission or promise that the chosen signing identity supports it.
public struct FeatureBuildRequirement: Sendable {
    public let owner: String
    public let infoPlist: [String: Plist.Value]
    public let entitlements: [String: Plist.Value]
    public let localizedInfoPlist: [String: [String: String]]

    public init(owner: String, infoPlist: [String: Plist.Value] = [:],
                entitlements: [String: Plist.Value] = [:],
                localizedInfoPlist: [String: [String: String]] = [:]) {
        self.owner = owner
        self.infoPlist = infoPlist
        self.entitlements = entitlements
        self.localizedInfoPlist = localizedInfoPlist
    }
}

public struct ComposedFeatureBuild: Sendable {
    public let infoPlist: [String: Plist.Value]
    public let entitlements: [String: Plist.Value]
    public let localizedInfoPlist: [String: [String: String]]

    /// Writes standard locale.lproj/InfoPlist.strings property-list resources.
    public func writeLocalizedInfoPlistStrings(to directory: String) throws {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for folder in try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        ) where folder.pathExtension == "lproj" {
            let stale = folder.appendingPathComponent("InfoPlist.strings")
            if FileManager.default.fileExists(atPath: stale.path) {
                try FileManager.default.removeItem(at: stale)
            }
        }
        for (locale, values) in localizedInfoPlist {
            let folder = root.appendingPathComponent("\(locale).lproj", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: values, format: .xml, options: 0)
            try data.write(to: folder.appendingPathComponent("InfoPlist.strings"), options: .atomic)
        }
    }
}

public struct FeatureBuildConfiguration: Sendable {
    public let features: [FeatureBuildRequirement]
    public let infoPlistResolutions: [String: Plist.Value]
    public let entitlementResolutions: [String: Plist.Value]
    public let localizedInfoPlistResolutions: [String: [String: String]]

    public init(features: [FeatureBuildRequirement] = [],
                infoPlistResolutions: [String: Plist.Value] = [:],
                entitlementResolutions: [String: Plist.Value] = [:],
                localizedInfoPlistResolutions: [String: [String: String]] = [:]) {
        self.features = features
        self.infoPlistResolutions = infoPlistResolutions
        self.entitlementResolutions = entitlementResolutions
        self.localizedInfoPlistResolutions = localizedInfoPlistResolutions
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
                stringSetKeys: ["com.apple.security.application-groups", "keychain-access-groups", "com.apple.developer.associated-domains"]),
            localizedInfoPlist: try mergeLocalizedInfoPlist()
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

    private func mergeLocalizedInfoPlist() throws -> [String: [String: String]] {
        let requestedLocales = Set(features.flatMap { $0.localizedInfoPlist.keys })
        for locale in localizedInfoPlistResolutions.keys where !requestedLocales.contains(locale) {
            throw Failure("Unused InfoPlist.strings resolution for locale \(locale)")
        }
        var output: [String: [String: String]] = [:]
        for locale in requestedLocales.sorted() {
            guard !locale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Failure("InfoPlist.strings locale must be nonempty")
            }
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
            guard locale.unicodeScalars.allSatisfy(allowed.contains) else {
                throw Failure("InfoPlist.strings locale contains invalid characters: \(locale)")
            }
            let requestedKeys = Set(features.flatMap { feature -> [String] in
                feature.localizedInfoPlist[locale].map { Array($0.keys) } ?? []
            })
            let resolutions = localizedInfoPlistResolutions[locale] ?? [:]
            for key in resolutions.keys where !requestedKeys.contains(key) {
                throw Failure("Unused InfoPlist.strings resolution for locale \(locale) key \(key)")
            }
            for key in requestedKeys.sorted() {
                guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw Failure("InfoPlist.strings key must be nonempty for locale \(locale)")
                }
                let requests = features.compactMap { feature in
                    feature.localizedInfoPlist[locale]?[key].map { (feature.owner, $0) }
                }
                if let resolution = resolutions[key] {
                    output[locale, default: [:]][key] = resolution
                } else if let first = requests.first?.1, requests.allSatisfy({ $0.1 == first }) {
                    output[locale, default: [:]][key] = first
                } else {
                    throw Failure("Conflicting InfoPlist.strings locale \(locale) key \(key) requested by \(requests.map(\.0).joined(separator: ", ")); add an explicit resolution")
                }
            }
        }
        return output
    }
}
