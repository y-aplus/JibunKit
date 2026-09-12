#if os(iOS)
import CounterIntegration
import JibunKitCore
import ReminderIntegration
import Foundation
import CoreSpotlight
import WidgetKit

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
    static let management = makeManagement()

    // Keep closure isolation and defaults out of a nested static initializer.
    // These factories also leave one activity dispatcher per App/scene owner.
    private static func makeManagement() -> MiniAppManagement {
        let registrations: [MiniAppManagement.Registration] = all.map { definition in
            MiniAppManagement.Registration(
                id: definition.id, lifetime: definition.lifetime, removal: definition.removal,
                unregister: {
                    try await definition.onUnregister?()
                    let context = MiniAppContext(id: definition.id)
                    await context.removeAllOwnedNotifications()
                    try context.replaceNotificationCategories(with: [])
                    try await MiniAppSpotlightNamespace(context: context).deleteAll(from: .default())
                },
                enable: {
                    try MiniAppContext(id: definition.id).replaceNotificationCategories(with: definition.notificationCategories)
                }
            )
        }
        return MiniAppManagement(
            registrations: registrations, defaults: managementDefaults, consents: consents,
            coordinator: MiniAppRestoreCoordinator.shared,
            storageKey: MiniAppManagement.defaultStorageKey,
            onStatusChange: { _, _ in WidgetCenter.shared.reloadAllTimelines() }
        )
    }

    static func makeLifecycleDispatcher() -> MiniAppLifecycleDispatcher {
        var handlers: [@MainActor (MiniAppHostPhase) -> Void] = []
        for definition in all {
            guard let handler = definition.onHostPhaseChange else { continue }
            let gated: @MainActor (MiniAppHostPhase) -> Void = { phase in
                if management.isEnabled(definition.id) { handler(phase) }
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
                if management.isEnabled(definition.id) { handler(activity) }
            })
        }
        return MiniAppSceneActivityDispatcher(handlers: handlers)
    }

    static var enabled: [MiniAppDefinition] { all.filter { management.isEnabled($0.id) } }
    static var registeredIDs: Set<MiniAppID> { Set(enabled.map(\.id)) }

    static func definition(for id: MiniAppID) -> MiniAppDefinition? {
        guard management.isEnabled(id) else { return nil }
        return all.first { $0.id == id }
    }

    private static func makeRegistry(
        _ miniApps: [MiniAppDefinition]
    ) -> [MiniAppDefinition] {
        precondition(
            Set(miniApps.map(\.id)).count == miniApps.count,
            "Mini-app IDs must be unique."
        )
        return miniApps
    }
}
#endif
