#if os(iOS)
import JibunKitCore
import Foundation
import Observation
import SwiftUI
import OSLog

@MainActor
@Observable
final class AppNavigation {
    private(set) var activeID: MiniAppID?
    private(set) var stackID = UUID()
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
        guard activeID != owner else { return }
        activeID = owner
        stackID = UUID()
    }

    func path(for owner: MiniAppID?) -> NavigationPath {
        guard let owner else { return NavigationPath() }
        return paths[owner] ?? NavigationPath([owner])
    }

    /// A departing NavigationStack may still write its binding. Its captured
    /// owner must never update the newly selected Feature's path.
    func update(_ path: NavigationPath, for owner: MiniAppID?) {
        guard let owner, owner == activeID else { return }
        if path.isEmpty {
            // A native back/pop to the launcher explicitly unwinds this stack.
            paths.removeValue(forKey: owner)
            select(nil)
        } else {
            paths[owner] = path
        }
    }

    func showList() { select(nil) }

    func resetCurrentPath() {
        guard let activeID else { return }
        paths.removeValue(forKey: activeID)
    }

    func openURL(_ url: URL) {
        if url.scheme?.lowercased() == "jibunkit" {
            if let route = MiniAppLink.resolveRoute(url, registeredIDs: MiniAppRegistry.registeredIDs) {
                open(route)
            }
            return
        }
        let registrations = MiniAppRegistry.all.compactMap { definition in
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
}

/// Process notifications need a target selector, not a process-wide UI path.
@MainActor
enum AppSceneRouting {
    static let shared = MiniAppSceneRouter()
}
#endif
