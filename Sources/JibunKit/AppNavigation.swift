#if os(iOS)
import JibunKitCore
import Foundation
import Observation
import SwiftUI
import OSLog
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppNavigation {
    enum HostSheet: String, Identifiable { case backup, management, incoming, search; var id: String { rawValue } }
    struct SearchContinuation { let query: String; let routes: [MiniAppRoute] }
    var hostSheet: HostSheet?
    private var queuedHostSheet: HostSheet?
    private(set) var searchContinuation: SearchContinuation?
    private var chosenSearchRoute: MiniAppRoute?
    var preparedIncoming: MiniAppPreparedIncoming?
    var incomingError: String?
    private(set) var isPreparingIncoming = false
    private var incomingTask: Task<Void, Never>?
    private(set) var activeID: MiniAppID?
    private(set) var stackID = UUID()
    private var selectionTask: Task<Void, Never>?
    private var pendingOwner: MiniAppID?
    private var paths: [MiniAppID: NavigationPath] = [:]

    // Values belong to a Feature within this scene. Switching changes the owner
    // being displayed, rather than overwriting another Feature's path.
    var path: NavigationPath {
        get { path(for: activeID) }
        set { update(newValue, for: activeID) }
    }

    var pathBinding: Binding<NavigationPath> {
        let owner = activeID
        let identity = stackID
        return Binding(
            get: { self.path(for: owner) },
            set: { [weak self] path in
                guard let self, self.stackID == identity else { return }
                self.update(path, for: owner)
            }
        )
    }

    private func select(_ owner: MiniAppID?) {
        pendingOwner = owner
        guard selectionTask == nil else { return }
        guard activeID != owner else { return }
        if let previous = MiniAppRegistry.all.first(where: { $0.id == activeID })?.presentations,
           previous.hasPendingPresentations {
            // The old root must stay mounted while its native dismissal is
            // acknowledged. Repeated navigation requests keep the latest owner.
            selectionTask = Task { @MainActor in
                await previous.dismissForNavigation()
                let next = pendingOwner
                commitSelection(next)
                selectionTask = nil
            }
        } else {
            commitSelection(owner)
        }
    }

    private func commitSelection(_ owner: MiniAppID?) {
        if let old = activeID, !MiniAppRegistry.management.isEnabled(old) { paths.removeValue(forKey: old) }
        activeID = owner.flatMap { MiniAppRegistry.management.isEnabled($0) ? $0 : nil }
        if let activeID { MiniAppRegistry.recordUse(activeID) }
        stackID = UUID()
        presentQueuedHostSheet()
    }

    func requestHostSheet(_ sheet: HostSheet) {
        if hostSheet == sheet { return }
        queuedHostSheet = sheet
        // A backup or management operation may own the current host sheet.
        // Incoming OS events wait for its actual dismissal instead of tearing
        // down the screen (and its in-progress confirmation/operation).
        guard hostSheet == nil else { return }
        showList()
        presentQueuedHostSheet()
    }

    func hostSheetDidDismiss() {
        if let route = chosenSearchRoute {
            chosenSearchRoute = nil
            searchContinuation = nil
            open(route)
        }
        presentQueuedHostSheet()
    }

    /// Spotlight's "Search in App": one accepting Feature opens directly;
    /// several are offered as a choice; none leaves the launcher visible.
    func continueSearch(_ query: String) {
        let registrations = MiniAppRegistry.enabled.compactMap { definition in
            definition.searchDestination.map { MiniAppSearchContinuation.Registration(id: definition.id, destination: $0) }
        }
        let routes = MiniAppSearchContinuation.candidates(
            for: query, registrations: registrations, registeredIDs: MiniAppRegistry.registeredIDs
        ).filter { MiniAppRegistry.definition(for: $0.id)?.navigationPath(for: $0.destination ?? "") != nil }
        switch routes.count {
        case 0: showList()
        case 1: open(routes[0])
        default:
            searchContinuation = SearchContinuation(query: query, routes: routes)
            requestHostSheet(.search)
        }
    }

    /// A continued activity reaches only the Feature that declared its type.
    func continueUserActivity(_ activity: NSUserActivity) {
        let registrations = MiniAppRegistry.userActivityRegistrations(
            MiniAppRegistry.enabled.filter { MiniAppRegistry.launchState.errors[$0.id] == nil })
        if let route = MiniAppUserActivityRouter.route(for: activity, registrations: registrations,
                                                       registeredIDs: MiniAppRegistry.registeredIDs) {
            open(route)
        }
    }

    /// Opens after the sheet is actually dismissed, like other host sheets.
    func chooseSearchRoute(_ route: MiniAppRoute) {
        chosenSearchRoute = route
        hostSheet = nil
    }

    private func presentQueuedHostSheet() {
        guard activeID == nil, hostSheet == nil, let next = queuedHostSheet else { return }
        hostSheet = next
        queuedHostSheet = nil
    }

    func receiveExternalFile(_ url: URL) {
        guard incomingTask == nil, preparedIncoming == nil else {
            incomingError = "先に現在の受信を保存またはキャンセルしてから、もう一度ファイルを開いてください。"
            requestHostSheet(.incoming)
            return
        }
        incomingError = nil
        isPreparingIncoming = true
        requestHostSheet(.incoming)
        let accessed = url.startAccessingSecurityScopedResource()
        incomingTask = Task { @MainActor in
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
                isPreparingIncoming = false
                incomingTask = nil
            }
            let copy = Task.detached {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("jibunkit-open-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                do {
                    let destination = directory.appendingPathComponent(UUID().uuidString)
                    try MiniAppIncomingFileAccess.copy(from: url, to: destination)
                    let type = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
                    return MiniAppPreparedIncoming(inputs: [.file(destination, typeIdentifier: type, displayName: url.lastPathComponent)], directoryURL: directory)
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    throw error
                }
            }
            do {
                let prepared = try await withTaskCancellationHandler { try await copy.value } onCancel: { copy.cancel() }
                if Task.isCancelled { try? prepared.removeTemporaryFiles() }
                else { preparedIncoming = prepared }
            } catch is CancellationError { }
            catch { incomingError = error.localizedDescription }
        }
    }

    func discardPreparedIncoming() {
        incomingTask?.cancel()
        if let preparedIncoming { try? preparedIncoming.removeTemporaryFiles() }
        preparedIncoming = nil
        incomingError = nil
    }

    func path(for owner: MiniAppID?) -> NavigationPath {
        guard let owner else { return NavigationPath() }
        return paths[owner] ?? NavigationPath()
    }

    /// A departing NavigationStack may still write its binding. Its captured
    /// owner must never update the newly selected Feature's path.
    func update(_ path: NavigationPath, for owner: MiniAppID?) {
        guard let owner, owner == activeID else { return }
        // An empty path is this Feature's root, not the launcher. The Feature
        // root is actual stack content, so its destination registrations exist
        // before SwiftUI resolves an incoming multi-level path.
        paths[owner] = path
    }

    func showList() { select(nil) }

    func openURL(_ url: URL) {
        if url.isFileURL { receiveExternalFile(url); return }
        if url.scheme?.lowercased() == "jibunkit" {
            if let route = MiniAppLink.resolveRoute(url, registeredIDs: MiniAppRegistry.registeredIDs) {
                open(route)
            }
            return
        }
        let registrations = MiniAppRegistry.enabled.compactMap { definition in
            definition.resolveIncomingURL.map {
                MiniAppURLRouter.Registration(id: definition.id, resolve: $0)
            }
        }
        do {
            if let route = try MiniAppURLRouter.resolve(url, registrations: registrations) { open(route) }
        } catch {
            // URLs may carry private query values; diagnostics contain only the
            // registration failure and owner identities, never the URL itself.
            Logger(subsystem: "com.jibunkit.app", category: "IncomingURL")
                .error("Incoming URL routing rejected: \(String(describing: error), privacy: .private)")
        }
    }

    func open(_ route: MiniAppRoute) {
        guard MiniAppRegistry.management.isEnabled(route.id) else { return }
        if let destination = route.destination {
            guard let next = MiniAppRegistry.definition(for: route.id)?.navigationPath(for: destination) else { return }
            paths[route.id] = next
            select(route.id)
        } else {
            // Existing root URLs/notifications explicitly address the entry.
            // Menu selection resumes; an explicit route replaces only its owner.
            guard MiniAppRegistry.registeredIDs.contains(route.id) else { return }
            paths.removeValue(forKey: route.id)
            select(route.id)
        }
    }

    func openNotificationRoute(_ route: MiniAppRoute?) {
        guard let route else { showList(); return }
        open(route)
    }

    func open(_ miniAppID: MiniAppID) {
        guard MiniAppRegistry.registeredIDs.contains(miniAppID) else {
            showList()
            return
        }
        select(miniAppID)
    }

    func openNotificationTarget(_ miniAppID: MiniAppID?) {
        guard let miniAppID else {
            showList()
            return
        }
        open(miniAppID)
    }

    func discardUnavailableOwners() {
        paths = paths.filter { $0.key == activeID || MiniAppRegistry.management.isEnabled($0.key) }
        if let activeID, !MiniAppRegistry.management.isEnabled(activeID) { showList() }
    }
}

/// Process notifications need a target selector, not a process-wide UI path.
@MainActor
enum AppSceneRouting {
    static let shared = MiniAppSceneRouter()
    static let windows = MiniAppWindowSceneRegistry()
}
#endif
