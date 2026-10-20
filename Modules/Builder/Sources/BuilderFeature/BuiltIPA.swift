import Foundation

public enum BuiltIPAError: Error, Equatable, LocalizedError {
    case notConfigured
    case noBuild
    case building
    case failed

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            BuilderText.localized("Enter the repository and a GitHub token in Build first.")
        case .noBuild:
            BuilderText.localized("No build has been requested in Build yet.")
        case .building:
            BuilderText.localized("The build has not finished yet. Try again in a few minutes.")
        case .failed:
            BuilderText.localized("The last build failed. Open Build to see why.")
        }
    }
}

/// The IPA of the last build requested in Build. The Shortcuts action that
/// passes it to SideStore reads it from here, without the Build screen.
public enum BuiltIPA {
    /// The name of the shortcut that Build runs to install with SideStore.
    public static var shortcutName: String { BuilderText.localized("Install JibunKit") }

    /// Opens the Shortcuts app and runs the shortcut named `name`.
    public static func shortcutURL(named name: String) -> URL {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        return components.url!
    }

    /// Where the IPA of `run` is kept.
    public static func file(for run: BuildRun, in directory: URL) -> URL {
        directory
            .appendingPathComponent("build-\(run.id)", isDirectory: true)
            .appendingPathComponent(GitHubBuildClient.ipaName)
    }

    /// Follows the last requested build until now and returns its IPA,
    /// downloading it when this device does not have it yet.
    public static func latest(storage: any BuilderStorage, transport: any BuildHTTPTransport, ipaDirectory: URL,
                              now: Date = Date()) async throws -> URL {
        var state = try storage.loadState()
        guard let repository = state.repository, let token = try storage.token() else { throw BuiltIPAError.notConfigured }
        guard var request = state.request else { throw BuiltIPAError.noBuild }
        let client = GitHubBuildClient(repository: repository, token: token, transport: transport)
        if !(request.run?.isFinished ?? false) {
            request = try await client.refresh(request, now: now)
            state.request = request
            try storage.saveState(state)
        }
        guard case .finished(let run) = BuildProgress(request) else { throw BuiltIPAError.building }
        guard run.succeeded else { throw BuiltIPAError.failed }
        let file = file(for: run, in: ipaDirectory)
        if !FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await client.downloadIPA(runID: run.id, to: file)
        }
        return file
    }
}
