#if os(iOS)
import CounterIntegration
import JibunKitCore
import ReminderIntegration
import Foundation
import UIKit
import CoreSpotlight
import WidgetKit
import OSLog
import Observation

@MainActor @Observable
final class ContinuingSurfaceStatus {
    var errors: [MiniAppID: String] = [:]
    var pending: Set<MiniAppID> = []
}

@MainActor
enum MiniAppRegistry {
    static let all = makeRegistry([
        CounterMiniApp.definition,
        ReminderMiniApp.definition,
    ])

    static let consents = MiniAppConsentStore(defaults: .standard)
    // With no usable shared-group configuration, local management still works.
    // The Widget independently reports unavailable storage in that configuration.
    private static let managementDefaults = (try? MiniAppStorage.sharedDefaults()) ?? .standard
    static let incomingStore = Result { try MiniAppIncomingStore.shared() }
    private(set) static var incomingCatalogError: String?
    static let management = makeManagement()
    private static var continuingTasks: [MiniAppID: Task<Void, Never>] = [:]
    static let continuingStatus = ContinuingSurfaceStatus()
    static let launchState = MiniAppLaunchState()

    /// App-scoped work: leaving a Feature screen must not cancel OS activities.
    /// A cold launch or foreground transition rechecks daemon state. Per-owner
    /// tasks avoid duplicate subscriptions and do not make A wait for B.
    static func reconcileContinuingSurfaces(for owner: MiniAppID? = nil) {
        for definition in all where !definition.continuingSurfaces.isEmpty
            && (owner == nil || definition.id == owner) && management.isEnabled(definition.id)
            && launchState.errors[definition.id] == nil {
            let id = definition.id
            guard continuingTasks[id] == nil else { continue }
            let group = definition.continuingSurfaceGroup
            continuingStatus.pending.insert(id)
            continuingTasks[id] = Task {
                defer {
                    continuingTasks[id] = nil
                    continuingStatus.pending.remove(id)
                }
                do {
                    try await group.reconcile()
                    continuingStatus.errors[id] = nil
                } catch {
                    continuingStatus.errors[id] = error.localizedDescription
                    Logger(subsystem: "com.jibunkit.app", category: "ContinuingSurfaces")
                        .error("Reconciliation failed for \(id.rawValue, privacy: .public): \(error.localizedDescription)")
                }
            }
        }
    }

    // Keep closure isolation and defaults out of a nested static initializer.
    // These factories also leave one activity dispatcher per App/scene owner.
    private static func makeManagement() -> MiniAppManagement {
        let registrations: [MiniAppManagement.Registration] = all.map { definition in
            MiniAppManagement.Registration(
                id: definition.id, lifetime: definition.lifetime, removal: incomingRemoval(for: definition),
                externalAccess: MiniAppWindowOwnership.externalAccess(for: definition),
                unregister: {
                    #if DEBUG
                    let started = Date()
                    print("MINIAPP_UNREGISTER owner=\(definition.id.rawValue) begin")
                    defer { print("MINIAPP_UNREGISTER owner=\(definition.id.rawValue) returned seconds=\(Date().timeIntervalSince(started))") }
                    #endif
                    if let destination = incomingDestination(for: definition) {
                        let store = try incomingStore.get()
                        try await Task.detached { try store.setAdmission(destination, enabled: false) }.value
                    }
                    try await definition.continuingSurfaceGroup.endOwned()
                    continuingStatus.errors[definition.id] = nil
                    try await definition.onUnregister?()
                    #if DEBUG
                    print("MINIAPP_UNREGISTER owner=\(definition.id.rawValue) feature-hook-complete")
                    #endif
                    let context = MiniAppContext(id: definition.id)
                    await context.removeAllOwnedNotifications()
                    try await MiniAppBadgeCoordinator.shared.removeCount(for: definition.id)
                    try context.replaceNotificationCategories(with: [])
                    #if DEBUG
                    print("MINIAPP_UNREGISTER owner=\(definition.id.rawValue) notifications-complete spotlight-begin")
                    #endif
                    try await MiniAppSpotlightNamespace(context: context).deleteAll(from: .default())
                    #if DEBUG
                    print("MINIAPP_UNREGISTER owner=\(definition.id.rawValue) spotlight-complete")
                    #endif
                },
                enable: {
                    try MiniAppContext(id: definition.id).replaceNotificationCategories(with: definition.notificationCategories)
                    if let destination = incomingDestination(for: definition) {
                        let store = try incomingStore.get()
                        try await Task.detached { try store.setAdmission(destination, enabled: true) }.value
                    }
                }
            )
        }
        let result = MiniAppManagement(
            registrations: registrations, defaults: managementDefaults, consents: consents,
            coordinator: MiniAppRestoreCoordinator.shared,
            storageKey: MiniAppManagement.defaultStorageKey,
            onStatusChange: { _, _ in
                WidgetCenter.shared.reloadAllTimelines()
                ControlCenter.shared.reloadAllControls()
                refreshQuickActions()
                refreshBadge()
            }
        )
        AppSceneRouting.windows.bootstrapSuspendedOwners(all.filter { !result.isEnabled($0.id) }.map(\.id))
        do {
            try incomingStore.get().publish(all.filter { result.isEnabled($0.id) }.compactMap(incomingDestination))
        } catch { incomingCatalogError = error.localizedDescription }
        return result
    }

    static func incomingDestination(for definition: MiniAppDefinition) -> MiniAppIncomingDestination? {
        guard let provider = definition.incoming else { return nil }
        return .init(id: definition.id, title: definition.title, typeIdentifiers: provider.typeIdentifiers)
    }

    private static func incomingRemoval(for definition: MiniAppDefinition) -> MiniAppRemovalProvider? {
        guard definition.incoming != nil else { return definition.removal }
        let store = incomingStore
        let owner = definition.id
        let original = definition.removal
        return MiniAppRemovalProvider(id: owner,
            dataDescription: [original?.dataDescription, String(localized: "Unimported shared data")].compactMap { $0 }.formatted(.list(type: .and))) {
                try await original?.removeData()
                let inbox = try store.get()
                try await Task.detached { try inbox.removeOwnedData(for: owner) }.value
            }
    }

    static func makeLifecycleDispatcher() -> MiniAppLifecycleDispatcher {
        var handlers: [@MainActor (MiniAppHostPhase) -> Void] = [{ phase in
            if phase == .active { reconcileContinuingSurfaces() }
        }]
        for definition in all {
            guard let handler = definition.onHostPhaseChange else { continue }
            let gated: @MainActor (MiniAppHostPhase) -> Void = { phase in
                if management.isEnabled(definition.id), launchState.errors[definition.id] == nil { handler(phase) }
            }
            handlers.append(gated)
        }
        return MiniAppLifecycleDispatcher(handlers: handlers)
    }

    static func makeSceneActivityDispatcher() -> MiniAppSceneActivityDispatcher {
        var handlers: [MiniAppSceneActivityDispatcher.Registration] = []
        for definition in all {
            guard let handler = definition.onSceneActivityChange else { continue }
            handlers.append(.init(id: definition.id) { activity in
                if management.isEnabled(definition.id), launchState.errors[definition.id] == nil { handler(activity) }
            })
        }
        return MiniAppSceneActivityDispatcher(handlers: handlers)
    }

    static let recentUsage = MiniAppRecentUsage(defaults: .standard)

    static func recordUse(_ id: MiniAppID) {
        recentUsage.record(id)
        refreshQuickActions()
    }

    /// Publishes Home Screen quick actions for enabled, launchable Features.
    static func refreshQuickActions() {
        let candidates = enabled.filter { launchState.errors[$0.id] == nil }.map {
            MiniAppQuickActions.Candidate(id: $0.id, title: $0.title, systemImage: $0.systemImage, actions: $0.quickActions)
        }
        UIApplication.shared.shortcutItems = MiniAppQuickActions.entries(recent: recentUsage.ids, candidates: candidates).map { entry in
            UIApplicationShortcutItem(
                type: MiniAppQuickActions.shortcutType, localizedTitle: entry.action.title,
                localizedSubtitle: entry.action.subtitle,
                icon: UIApplicationShortcutIcon(systemImageName: entry.action.systemImage),
                userInfo: MiniAppQuickActions.userInfo(for: entry).mapValues { $0 as NSString as any NSSecureCoding })
        }
    }

    /// Disabled owners stop contributing to the icon badge.
    static func refreshBadge() {
        let owners = registeredIDs
        Task {
            do { try await MiniAppBadgeCoordinator.shared.setEnabledOwners(owners) }
            catch {
                Logger(subsystem: "com.jibunkit.app", category: "Badge")
                    .error("Badge update failed: \(error.localizedDescription)")
            }
        }
    }

    /// Returns whether the item belonged to JibunKit and addressed an enabled Feature.
    @discardableResult
    static func performQuickAction(_ item: UIApplicationShortcutItem) -> Bool {
        guard let route = MiniAppQuickActions.route(type: item.type, userInfo: item.userInfo,
                                                    registeredIDs: registeredIDs) else { return false }
        AppSceneRouting.shared.open(route)
        return true
    }

    static func userActivityRegistrations(_ definitions: [MiniAppDefinition]) -> [MiniAppUserActivityRouter.Registration] {
        definitions.compactMap { definition in
            definition.userActivity.map { MiniAppUserActivityRouter.Registration(id: definition.id, handler: $0) }
        }
    }

    static var enabled: [MiniAppDefinition] { all.filter { management.isEnabled($0.id) } }
    static var registeredIDs: Set<MiniAppID> { Set(enabled.map(\.id)) }

    static func definition(for id: MiniAppID) -> MiniAppDefinition? {
        guard management.isEnabled(id), launchState.errors[id] == nil else { return nil }
        return all.first { $0.id == id }
    }

    /// Features under Modules/ that declare JibunKitFeature.json follow the
    /// hand-registered ones; see Tools/jibunkit-feature.py.
    private static func makeRegistry(
        _ registered: [MiniAppDefinition]
    ) -> [MiniAppDefinition] {
        validated(registered + ModuleFeatureRegistry.definitions)
    }

    private static func validated(
        _ miniApps: [MiniAppDefinition]
    ) -> [MiniAppDefinition] {
        precondition(
            Set(miniApps.map(\.id)).count == miniApps.count,
            "Mini-app IDs must be unique."
        )
        do {
            try MiniAppUserActivityRouter.validate(userActivityRegistrations(miniApps),
                reserved: [CSSearchableItemActionType, CSQueryContinuationActionType])
        } catch {
            preconditionFailure("Invalid Feature user activity types: \(error)")
        }
        return miniApps
    }
}
#endif
