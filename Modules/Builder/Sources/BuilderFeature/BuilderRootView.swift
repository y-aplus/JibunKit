#if os(iOS)
import Foundation
import Observation
import SwiftUI

public enum BuilderNotificationConsent: Sendable {
    case notDetermined, allowed, denied
}

/// An optional local notification at the time a build is usually finished, so
/// the app need not stay open. It is a reminder to check, not a completion
/// signal.
public struct BuilderNotifications: Sendable {
    public var consent: @MainActor @Sendable () -> BuilderNotificationConsent
    public var setConsent: @MainActor @Sendable (Bool) -> Void
    public var schedule: @Sendable (Date) async throws -> Void
    public var cancel: @Sendable () async -> Void

    public init(consent: @escaping @MainActor @Sendable () -> BuilderNotificationConsent,
                setConsent: @escaping @MainActor @Sendable (Bool) -> Void,
                schedule: @escaping @Sendable (Date) async throws -> Void,
                cancel: @escaping @Sendable () async -> Void) {
        self.consent = consent
        self.setConsent = setConsent
        self.schedule = schedule
        self.cancel = cancel
    }
}

public struct BuilderEnvironment: Sendable {
    public var storage: any BuilderStorage
    public var transport: any BuildHTTPTransport
    /// Where downloaded IPAs are kept until the next build.
    public var ipaDirectory: URL
    public var notifications: BuilderNotifications?

    public init(storage: any BuilderStorage, transport: any BuildHTTPTransport, ipaDirectory: URL,
                notifications: BuilderNotifications? = nil) {
        self.storage = storage
        self.transport = transport
        self.ipaDirectory = ipaDirectory
        self.notifications = notifications
    }
}

@MainActor
@Observable
final class BuilderModel {
    let environment: BuilderEnvironment
    var slug = ""
    var branch = "main"
    var tokenInput = ""
    var hasToken = false
    var state = BuilderState()
    var ipaURL: URL?
    var message: String?
    var isError = false
    var isWorking = false

    init(environment: BuilderEnvironment) {
        self.environment = environment
        do {
            state = try environment.storage.loadState()
            hasToken = try environment.storage.token() != nil
        } catch {
            show(error)
        }
        slug = state.repository?.slug ?? ""
        branch = state.repository?.branch ?? "main"
        if case .finished(let run) = progress, run.succeeded,
           FileManager.default.fileExists(atPath: ipaFile(for: run).path) {
            ipaURL = ipaFile(for: run)
        }
    }

    var progress: BuildProgress { BuildProgress(state.request) }

    var isConfigured: Bool { state.repository != nil && hasToken }

    var canBuild: Bool {
        guard isConfigured, !isWorking else { return false }
        switch progress {
        case .waiting, .running: return false
        case .none, .finished: return true
        }
    }

    func saveSettings() {
        guard let repository = BuildRepository(slug: slug, branch: branch) else {
            show(String(localized: "Enter the repository as OWNER/REPO.", bundle: .module), isError: true)
            return
        }
        do {
            let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                try environment.storage.setToken(token)
                tokenInput = ""
                hasToken = true
            }
            state.repository = repository
            try environment.storage.saveState(state)
            show(String(localized: "Saved", bundle: .module), isError: false)
        } catch {
            show(error)
        }
    }

    func removeToken() {
        do {
            try environment.storage.setToken(nil)
            hasToken = false
            show(String(localized: "Removed the token", bundle: .module), isError: false)
        } catch {
            show(error)
        }
    }

    func startBuild(notify: Bool) async {
        guard let client = client() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let requestedAt = Date()
            try await client.requestBuild()
            removeDownloadedIPAs()
            state.request = BuildRequest(requestedAt: requestedAt)
            try environment.storage.saveState(state)
            if notify, let notifications = environment.notifications {
                await notifications.cancel()
                try? await notifications.schedule(requestedAt + BuildTiming.expectedDuration)
            }
            show(String(localized: "Requested a build. You can close the app; it usually takes a few minutes.", bundle: .module),
                 isError: false)
        } catch {
            show(error)
        }
    }

    func refresh() async {
        guard let request = state.request, !(request.run?.isFinished ?? false), let client = client() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            state.request = try await client.refresh(request)
            try environment.storage.saveState(state)
            message = nil
        } catch {
            show(error)
        }
    }

    func downloadIPA() async {
        guard case .finished(let run) = progress, run.succeeded, let client = client() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let file = ipaFile(for: run)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await client.downloadIPA(runID: run.id, to: file)
            ipaURL = file
            message = nil
        } catch {
            show(error)
        }
    }

    private func client() -> GitHubBuildClient? {
        do {
            guard let repository = state.repository, let token = try environment.storage.token() else { return nil }
            return GitHubBuildClient(repository: repository, token: token, transport: environment.transport)
        } catch {
            show(error)
            return nil
        }
    }

    private func ipaFile(for run: BuildRun) -> URL {
        environment.ipaDirectory
            .appendingPathComponent("build-\(run.id)", isDirectory: true)
            .appendingPathComponent(GitHubBuildClient.ipaName)
    }

    private func removeDownloadedIPAs() {
        try? FileManager.default.removeItem(at: environment.ipaDirectory)
        ipaURL = nil
    }

    private func show(_ error: Error) {
        show(error.localizedDescription, isError: true)
    }

    private func show(_ text: String, isError: Bool) {
        message = text
        self.isError = isError
    }
}

/// Builds this JibunKit's IPA in GitHub Actions and hands it to SideStore or
/// AltStore through the share sheet.
public struct BuilderRootView: View {
    @State private var model: BuilderModel
    @State private var askingNotificationConsent = false
    @Environment(\.scenePhase) private var scenePhase

    public init(environment: BuilderEnvironment) {
        _model = State(initialValue: BuilderModel(environment: environment))
    }

    public var body: some View {
        Form {
            buildSection
            settingsSection
            if let message = model.message {
                Section {
                    Text(message)
                        .foregroundStyle(model.isError ? .red : .secondary)
                        .accessibilityIdentifier("builder.message")
                }
            }
        }
        .navigationTitle(Text("Build", bundle: .module))
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .alert(Text("Notify When the Build Is Likely Done?", bundle: .module), isPresented: $askingNotificationConsent) {
            Button { answerNotificationConsent(true) } label: { Text("Allow", bundle: .module) }
            Button(role: .cancel) { answerNotificationConsent(false) } label: { Text("Don’t Allow", bundle: .module) }
        } message: {
            Text("JibunKit sends one notification a few minutes after each build request, so you need not keep the app open.",
                 bundle: .module)
        }
    }

    @ViewBuilder private var buildSection: some View {
        Section {
            progressRow
            if let ipaURL = model.ipaURL {
                ShareLink(item: ipaURL) {
                    Label { Text("Share the IPA", bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") }
                }
                .accessibilityIdentifier("builder.share")
            } else if case .finished(let run) = model.progress, run.succeeded {
                Button { Task { await model.downloadIPA() } } label: { Text("Download the IPA", bundle: .module) }
                    .disabled(model.isWorking)
            }
            Button { requestBuild() } label: { Text("Build the IPA", bundle: .module) }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canBuild)
                .accessibilityIdentifier("builder.build")
        } footer: {
            if !model.isConfigured {
                Text("Enter the repository and a GitHub token below first.", bundle: .module)
            }
        }
    }

    @ViewBuilder private var progressRow: some View {
        switch model.progress {
        case .none:
            Text("No build requested yet", bundle: .module).foregroundStyle(.secondary)
        case .waiting(let since):
            HStack {
                ProgressView()
                Text("Waiting for GitHub to start the build (requested \(since, style: .time))", bundle: .module)
            }
        case .running(let run):
            HStack {
                ProgressView()
                Text("Building since \(run.createdAt, style: .time)", bundle: .module)
            }
            Link(destination: run.htmlURL) { Text("Open the run on GitHub", bundle: .module) }
        case .finished(let run):
            if run.succeeded {
                Label { Text("Built at \(run.createdAt, style: .time)", bundle: .module) } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } else {
                Label { Text("The build failed", bundle: .module) } icon: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
                Link(destination: run.htmlURL) { Text("Open the run on GitHub", bundle: .module) }
            }
        }
    }

    @ViewBuilder private var settingsSection: some View {
        Section {
            TextField(String(localized: "OWNER/REPO", bundle: .module), text: $model.slug)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("builder.repository")
            TextField(String(localized: "Branch", bundle: .module), text: $model.branch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(model.hasToken ? String(localized: "Token saved; enter to replace", bundle: .module)
                                       : String(localized: "GitHub token", bundle: .module),
                        text: $model.tokenInput)
            Button { model.saveSettings() } label: { Text("Save", bundle: .module) }
            if model.hasToken {
                Button(role: .destructive) { model.removeToken() } label: { Text("Remove the Token", bundle: .module) }
            } else if let repository = BuildRepository(slug: model.slug, branch: model.branch) {
                Link(destination: repository.tokenCreationURL) { Text("Create a Token on GitHub", bundle: .module) }
                    .accessibilityIdentifier("builder.createToken")
            }
        } header: {
            Text("Repository", bundle: .module)
        } footer: {
            Text("The token needs read and write access to Actions and read access to Contents. GitHub fills these in from the button; under Repository access, choose only this repository. The repository needs the Build IPA (quick) workflow.",
                 bundle: .module)
        }
    }

    private func requestBuild() {
        guard let notifications = model.environment.notifications else {
            Task { await model.startBuild(notify: false) }
            return
        }
        switch notifications.consent() {
        case .notDetermined: askingNotificationConsent = true
        case .allowed: Task { await model.startBuild(notify: true) }
        case .denied: Task { await model.startBuild(notify: false) }
        }
    }

    private func answerNotificationConsent(_ allowed: Bool) {
        model.environment.notifications?.setConsent(allowed)
        Task { await model.startBuild(notify: allowed) }
    }
}
#endif
