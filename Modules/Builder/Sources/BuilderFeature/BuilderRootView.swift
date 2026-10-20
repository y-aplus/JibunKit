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
    /// Empty means `BuildRepository.defaultUpstream`.
    var upstreamSlug = ""
    var upstreamStatus: UpstreamStatus?
    var upstreamError: String?
    var tokenInput = ""
    var hasToken = false
    var state = BuilderState()
    /// The branch's JibunKitImports.json, read when the screen refreshes.
    var imported: [ImportedFeature] = []
    /// The branch's draft Features, read when the screen refreshes.
    var drafts: [DraftFeature] = []
    /// The screenshots of the last Simulator check or migration, read once it has finished.
    var screenshots: [LaunchScreenshot] = []
    private var screenshotsRunID: Int?
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
        upstreamSlug = state.upstream?.slug ?? ""
        if case .finished(let run) = progress, run.succeeded,
           FileManager.default.fileExists(atPath: ipaFile(for: run).path) {
            ipaURL = ipaFile(for: run)
        }
    }

    var progress: BuildProgress { BuildProgress(state.request) }

    var isConfigured: Bool { state.repository != nil && hasToken }

    var upstream: BuildRepository { state.upstream ?? .defaultUpstream }

    /// Upstream JibunKit's own repository has no upstream to compare with.
    var comparesWithUpstream: Bool { isConfigured && state.repository?.slug != upstream.slug }

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
        let upstreamText = upstreamSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        let upstream = BuildRepository(slug: upstreamText, branch: "main")
        guard upstreamText.isEmpty || upstream != nil else {
            show(String(localized: "Enter the upstream as OWNER/REPO, or leave it empty.", bundle: .module), isError: true)
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
            state.upstream = upstream == .defaultUpstream ? nil : upstream
            upstreamSlug = state.upstream?.slug ?? ""
            try environment.storage.saveState(state)
            upstreamStatus = nil
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
        await refreshBuild()
        await refreshImport()
        await loadImported()
        await loadScreenshots()
        await loadUpstream()
    }

    func loadUpstream() async {
        guard comparesWithUpstream, let client = client() else {
            upstreamStatus = nil
            return
        }
        do {
            upstreamStatus = try await client.upstreamStatus(of: upstream)
            upstreamError = nil
        } catch {
            upstreamError = error.localizedDescription
        }
    }

    private func refreshBuild() async {
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

    var importProgress: BuildProgress { state.importRequest?.progress ?? .none }

    var isImporting: Bool {
        switch importProgress {
        case .waiting, .running: true
        case .none, .finished: false
        }
    }

    var canImport: Bool { isConfigured && !isWorking && !isImporting }

    func startImport(_ operation: FeatureImportOperation) async {
        guard let client = client() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let requestedAt = Date()
            try await client.requestImport(operation)
            state.importRequest = ImportRequest(operation: operation, requestedAt: requestedAt)
            try environment.storage.saveState(state)
            screenshots = []
            screenshotsRunID = nil
            switch operation {
            case .inspect:
                show(String(localized: "Requested. GitHub writes the report in about a minute.", bundle: .module), isError: false)
            case .migrate:
                show(String(localized: "Requested. GitHub writes the draft and compiles it; this takes about 10 minutes.",
                            bundle: .module), isError: false)
            case .connect:
                show(String(localized: "Requested. GitHub compiles with the draft connected and connects it only if that passes; this takes about 10 minutes.",
                            bundle: .module), isError: false)
            case .launch:
                show(String(localized: "Requested. GitHub builds the app for the iOS Simulator and opens each mini app; this takes about 15 minutes.",
                            bundle: .module), isError: false)
            case .add, .update, .remove:
                show(String(localized: "Requested. GitHub commits the result to the branch in about a minute.", bundle: .module),
                     isError: false)
            }
        } catch {
            show(error)
        }
    }

    /// Follows the last import without blocking the other buttons, so the
    /// screen can poll it while it runs.
    func refreshImport() async {
        guard let request = state.importRequest, !(request.run?.isFinished ?? false) || request.report == nil,
              let client = client() else { return }
        do {
            let updated = try await client.refresh(request)
            state.importRequest = updated
            try environment.storage.saveState(state)
            if updated.run?.isFinished == true, request.run?.isFinished != true {
                await loadImported()
                await loadScreenshots()
            }
        } catch {
            show(error)
        }
    }

    func loadImported() async {
        guard let client = client() else {
            imported = []
            return
        }
        do {
            imported = try await client.importedFeatures()
            drafts = try await client.drafts()
        } catch {
            show(error)
        }
    }

    func loadScreenshots() async {
        guard let request = state.importRequest, request.operation.takesScreenshots,
              let run = request.run, run.isFinished, run.id != screenshotsRunID, let client = client() else { return }
        do {
            screenshots = try await client.launchScreenshots(runID: run.id)
            screenshotsRunID = run.id
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
        BuiltIPA.file(for: run, in: environment.ipaDirectory)
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

/// Builds this JibunKit's IPA in GitHub Actions and hands it to SideStore
/// through a shortcut, or to another app through the share sheet.
public struct BuilderRootView: View {
    @State private var model: BuilderModel
    @State private var askingNotificationConsent = false
    @State private var showingImportForm = false
    @State private var removing: ImportedFeature?
    @State private var removingDraft: DraftFeature?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    public init(environment: BuilderEnvironment) {
        _model = State(initialValue: BuilderModel(environment: environment))
    }

    public var body: some View {
        Form {
            buildSection
            if model.comparesWithUpstream {
                upstreamSection
            }
            importSection
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
        // An import takes about a minute, so follow it while the screen is open.
        .task(id: model.isImporting) {
            while model.isImporting, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await model.refreshImport()
            }
        }
        .sheet(isPresented: $showingImportForm) {
            ImportFeatureForm { operation in Task { await model.startImport(operation) } }
        }
        .confirmationDialog(Text("Remove the Imported Feature?", bundle: .module),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { feature in
            Button(role: .destructive) {
                Task { await model.startImport(.remove(name: feature.name)) }
            } label: { Text("Remove", bundle: .module) }
        } message: { feature in
            Text("GitHub deletes Modules/\(feature.name) and commits the change. To delete the data it saved on this iPhone, do that in Manage Mini Apps before you install a build without it.",
                 bundle: .module)
        }
        .confirmationDialog(Text("Remove the Draft?", bundle: .module),
                            isPresented: Binding(get: { removingDraft != nil }, set: { if !$0 { removingDraft = nil } }),
                            titleVisibility: .visible, presenting: removingDraft) { draft in
            Button(role: .destructive) {
                Task { await model.startImport(.remove(name: draft.name)) }
            } label: { Text("Remove", bundle: .module) }
        } message: { draft in
            Text("GitHub deletes Modules/\(draft.name) and commits the change.", bundle: .module)
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
            if case .finished(let run) = model.progress, run.succeeded {
                Button { openURL(BuiltIPA.shortcutURL(named: BuiltIPA.shortcutName)) } label: {
                    Label { Text("Install with SideStore", bundle: .module) } icon: { Image(systemName: "arrow.down.app") }
                }
                .accessibilityIdentifier("builder.installWithSideStore")
            }
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
        Section {
            DisclosureGroup {
                Text("In the Shortcuts app, make a new shortcut and name it “\(BuiltIPA.shortcutName)”. In the search field at the bottom, search for JibunKit and add Get the Built JibunKit IPA, then search for SideStore and add its Install action. Touch and hold its IPA File and choose the first action's result.",
                     bundle: .module)
                    .font(.callout)
            } label: {
                Text("Set Up Install with SideStore", bundle: .module)
            }
        } footer: {
            Text("Install with SideStore runs that shortcut. It downloads the IPA of the last build and has SideStore install it.",
                 bundle: .module)
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

    @ViewBuilder private var upstreamSection: some View {
        Section {
            if let status = model.upstreamStatus {
                switch status.newCommits {
                case 0?:
                    Label { Text("Every upstream change is merged", bundle: .module) } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                case let count?:
                    Label { Text("Changes not merged yet: \(count)", bundle: .module) } icon: {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
                    }
                case nil:
                    Label { Text("More than \(UpstreamStatus.counted) changes not merged yet", bundle: .module) } icon: {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
                    }
                }
                if let release = status.latestRelease {
                    LabeledContent { Text(verbatim: release) } label: { Text("Latest release", bundle: .module) }
                }
                if status.newCommits != 0 {
                    Link(destination: status.changesURL) { Text("See the Changes on GitHub", bundle: .module) }
                }
            } else if let error = model.upstreamError {
                Text(verbatim: error).foregroundStyle(.red)
            } else {
                HStack {
                    ProgressView()
                    Text("Comparing with upstream", bundle: .module)
                }
            }
        } header: {
            Text("Upstream: \(model.upstream.slug)", bundle: .module)
        } footer: {
            Text("Compared each time this screen opens. Merge the changes on a computer as docs/updating.md describes, then build the IPA.",
                 bundle: .module)
        }
        .accessibilityIdentifier("builder.upstream")
    }

    @ViewBuilder private var importSection: some View {
        Section {
            if let request = model.state.importRequest {
                importStatus(request)
            }
            ForEach(model.imported) { feature in
                Menu {
                    Button { Task { await model.startImport(.update(name: feature.name, ref: "")) } } label: {
                        Label { Text("Update", bundle: .module) } icon: { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                    Button(role: .destructive) { removing = feature } label: {
                        Label { Text("Remove", bundle: .module) } icon: { Image(systemName: "trash") }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: feature.name).foregroundStyle(.primary)
                        Text(verbatim: feature.path.isEmpty ? feature.repository : "\(feature.repository) · \(feature.path)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: "\(Self.refLabel(feature.ref)) · \(feature.commit.prefix(7))")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .disabled(!model.canImport)
            }
            ForEach(model.drafts) { draft in
                Menu {
                    Button { Task { await model.startImport(.connect(name: draft.name)) } } label: {
                        Label { Text("Connect", bundle: .module) } icon: { Image(systemName: "link") }
                    }
                    Button { Task { await model.startImport(.launch(draft: draft.name)) } } label: {
                        Label { Text("Open in the Simulator", bundle: .module) } icon: { Image(systemName: "iphone") }
                    }
                    if let repository = model.state.repository,
                       let report = URL(string: "https://github.com/\(repository.slug)/blob/\(repository.branch)/Modules/\(draft.name)/MIGRATION.md") {
                        Link(destination: report) {
                            Label { Text("Open the Report on GitHub", bundle: .module) } icon: { Image(systemName: "doc.text") }
                        }
                    }
                    Button(role: .destructive) { removingDraft = draft } label: {
                        Label { Text("Remove", bundle: .module) } icon: { Image(systemName: "trash") }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: draft.name).foregroundStyle(.primary)
                        Text("Draft, not connected", bundle: .module).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!model.canImport)
            }
            Button { showingImportForm = true } label: { Text("Import a Feature", bundle: .module) }
                .disabled(!model.canImport)
                .accessibilityIdentifier("builder.import")
            Button { Task { await model.startImport(.launch(draft: "")) } } label: {
                Text("Open Every Mini App in the Simulator", bundle: .module)
            }
            .disabled(!model.canImport)
            .accessibilityIdentifier("builder.launch")
        } header: {
            Text("Features from Other Repositories", bundle: .module)
        } footer: {
            Text("GitHub copies the Feature into Modules and commits it to the branch below. Its code runs only when you build; build the IPA afterwards to include the change. The Simulator check opens each mini app of the branch and shows a screenshot of each, so a mini app that stops at launch is found before you install.",
                 bundle: .module)
        }
    }

    @ViewBuilder private func importStatus(_ request: ImportRequest) -> some View {
        let title = Self.title(of: request.operation)
        switch request.progress {
        case .none:
            EmptyView()
        case .waiting:
            HStack {
                ProgressView()
                Text("\(title): waiting for GitHub", bundle: .module)
            }
        case .running(let run):
            HStack {
                ProgressView()
                Text("\(title): running", bundle: .module)
            }
            Link(destination: run.htmlURL) { Text("Open the run on GitHub", bundle: .module) }
        case .finished(let run):
            if run.succeeded {
                Label { Text("\(title): done", bundle: .module) } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } else {
                Label { Text("\(title): stopped; see the report", bundle: .module) } icon: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
                Link(destination: run.htmlURL) { Text("Open the run on GitHub", bundle: .module) }
            }
            if let report = request.report, !report.isEmpty {
                DisclosureGroup {
                    Text(verbatim: report).font(.caption.monospaced()).textSelection(.enabled)
                } label: {
                    Text("Report", bundle: .module)
                }
            } else if request.report == nil {
                Text("The report is not available yet. Pull down to refresh.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.screenshots.isEmpty {
                screenshotStrip
            }
        }
    }

    private var screenshotStrip: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(model.screenshots) { screenshot in
                    VStack(spacing: 4) {
                        if let image = UIImage(data: screenshot.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        if screenshot.name == "home" {
                            Text("Mini app list", bundle: .module).font(.caption)
                        } else {
                            Text(verbatim: screenshot.name).font(.caption)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("builder.screenshots")
    }

    /// `add` records HEAD when no ref was given.
    static func refLabel(_ ref: String) -> String {
        ref == "HEAD" ? String(localized: "default branch", bundle: .module) : ref
    }

    static func title(of operation: FeatureImportOperation) -> String {
        switch operation {
        case let .add(repository, _, path, name):
            let subject = !name.isEmpty ? name : path.isEmpty ? repository : "\(repository) \(path)"
            return String(localized: "Import \(subject)", bundle: .module)
        case let .update(name, _):
            return String(localized: "Update \(name)", bundle: .module)
        case let .remove(name):
            return String(localized: "Remove \(name)", bundle: .module)
        case let .inspect(repository, _, path):
            let subject = path.isEmpty ? repository : "\(repository) \(path)"
            return String(localized: "Check \(subject)", bundle: .module)
        case let .migrate(_, _, _, name):
            return String(localized: "Migrate \(name)", bundle: .module)
        case let .connect(name):
            return String(localized: "Connect \(name)", bundle: .module)
        case let .launch(draft):
            return draft.isEmpty ? String(localized: "Simulator check", bundle: .module)
                                 : String(localized: "Simulator check of \(draft)", bundle: .module)
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
            LabeledContent {
                TextField(BuildRepository.defaultUpstream.slug, text: $model.upstreamSlug)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            } label: {
                Text("Upstream", bundle: .module)
            }
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

/// Asks for a repository to copy a Feature from, or to check. `OWNER/REPO` means GitHub.
private struct ImportFeatureForm: View {
    let onImport: (FeatureImportOperation) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var repository = ""
    @State private var ref = ""
    @State private var path = ""
    @State private var name = ""

    var body: some View {
        NavigationStack { // jibunkit: allow navigation-stack
            Form {
                Section {
                    TextField(String(localized: "https://github.com/OWNER/REPO", bundle: .module), text: $repository)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("builder.import.repository")
                } header: {
                    Text("Repository", bundle: .module)
                } footer: {
                    Text("To import, the directory must contain a JibunKit Feature: Package.swift and JibunKitFeature.json.",
                         bundle: .module)
                }
                Section {
                    TextField(String(localized: "Branch, tag or commit", bundle: .module), text: $ref)
                    TextField(String(localized: "Directory in the repository", bundle: .module), text: $path)
                    TextField(String(localized: "Name under Modules", bundle: .module), text: $name)
                } header: {
                    Text("Optional", bundle: .module)
                } footer: {
                    Text("Leave these empty to use the default branch, the repository root and a name from the URL.", bundle: .module)
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Section {
                    Button {
                        onImport(.inspect(repository: repositoryURL, ref: trimmed(ref), path: trimmed(path)))
                        dismiss()
                    } label: { Text("Check Compatibility", bundle: .module) }
                        .disabled(repositoryURL.isEmpty)
                        .accessibilityIdentifier("builder.inspect")
                } footer: {
                    Text("Reads any repository, such as an ordinary iOS app, and reports what it needs to become a JibunKit Feature. Nothing is committed.",
                         bundle: .module)
                }
                Section {
                    Button {
                        onImport(.migrate(repository: repositoryURL, ref: trimmed(ref), path: trimmed(path), name: trimmed(name)))
                        dismiss()
                    } label: { Text("Migrate the App", bundle: .module) }
                        .disabled(repositoryURL.isEmpty || trimmed(name).isEmpty)
                        .accessibilityIdentifier("builder.migrate")
                } footer: {
                    Text("Copies an ordinary iOS app into Modules as a draft, makes the mechanical changes and compiles it. A draft does not change your builds; connect it once it compiles. Needs a name under Modules.",
                         bundle: .module)
                }
            }
            .navigationTitle(Text("Import a Feature", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onImport(.add(repository: repositoryURL, ref: trimmed(ref), path: trimmed(path), name: trimmed(name)))
                        dismiss()
                    } label: { Text("Import", bundle: .module) }
                        .disabled(repositoryURL.isEmpty)
                }
            }
        }
    }

    private var repositoryURL: String {
        BuildRepository(slug: repository, branch: "main").map { "https://github.com/\($0.slug)" } ?? trimmed(repository)
    }

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}
#endif
