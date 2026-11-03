import Foundation

/// The build of the running app. `Tools/package-ipa.sh` writes these keys into
/// the app's Info.plist on GitHub; a build made elsewhere has none, so Build
/// cannot tell whether a published build is newer.
public struct InstalledBuild: Equatable, Sendable {
    public static let runIDKey = "JibunKitBuildRunID"
    public static let commitKey = "JibunKitBuildCommit"

    public var runID: Int
    public var commit: String

    public init(runID: Int, commit: String) {
        self.runID = runID
        self.commit = commit
    }

    public init?(infoDictionary: [String: Any]?) {
        guard let text = infoDictionary?[Self.runIDKey] as? String, let runID = Int(text), runID > 0 else { return nil }
        self.init(runID: runID, commit: infoDictionary?[Self.commitKey] as? String ?? "")
    }

    public static var current: InstalledBuild? { InstalledBuild(infoDictionary: Bundle.main.infoDictionary) }
}

extension GitHubBuildClient {
    /// The newest successful build of the branch that has a `build-RUN_ID`
    /// prerelease with an IPA and was built after `installed`; nil when there
    /// is none. Run IDs grow over time, so a larger one is a later build.
    public func newerBuild(than installed: InstalledBuild) async throws -> BuildRun? {
        struct Release: Decodable {
            struct Asset: Decodable { let name: String }
            let tag_name: String
            let prerelease: Bool
            let assets: [Asset]
        }
        let releases = try decode([Release].self, from: try await send(
            path: "releases", query: [URLQueryItem(name: "per_page", value: "30")]))
        let candidates = releases.compactMap { release -> Int? in
            guard release.prerelease, release.tag_name.hasPrefix("build-"),
                  let id = Int(release.tag_name.dropFirst("build-".count)), id > installed.runID,
                  release.assets.contains(where: { $0.name == Self.ipaName }) else { return nil }
            return id
        }
        // The prerelease's target is a commit, so the run says which branch it built.
        struct Branch: Decodable { let head_branch: String? }
        for id in candidates.sorted(by: >) {
            let data: Data
            do {
                data = try await send(path: "actions/runs/\(id)")
            } catch BuildClientError.notFound {
                continue
            }
            guard try decode(Branch.self, from: data).head_branch == repository.branch else { continue }
            let run = try decode(BuildRun.self, from: data)
            if run.succeeded { return run }
        }
        return nil
    }
}
