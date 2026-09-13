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
    static let incomingStore = Result { try MiniAppIncomingStore.shared() }
    private(set) static var incomingCatalogError: String?
    static let management = makeManagement()

    // Keep closure isolation and defaults out of a nested static initializer.
    // These factories also leave one activity dispatcher per App/scene owner.
    private static func makeManagement() -> MiniAppManagement {
        let registrations: [MiniAppManagement.Registration] = all.map { definition in
            MiniAppManagement.Registration(
                id: definition.id, lifetime: definition.lifetime, removal: incomingRemoval(for: definition),
                unregister: {
                    if let destination = incomingDestination(for: definition) {
                        try incomingStore.get().setAdmission(destination, enabled: false)
                    }
                    try await definition.onUnregister?()
                    let context = MiniAppContext(id: definition.id)
                    await context.removeAllOwnedNotifications()
                    try context.replaceNotificationCategories(with: [])
                    try await MiniAppSpotlightNamespace(context: context).deleteAll(from: .default())
                },
                enable: {
                    try MiniAppContext(id: definition.id).replaceNotificationCategories(with: definition.notificationCategories)
                    if let destination = incomingDestination(for: definition) {
                        try incomingStore.get().setAdmission(destination, enabled: true)
                    }
                }
            )
        }
        let result = MiniAppManagement(
            registrations: registrations, defaults: managementDefaults, consents: consents,
            coordinator: MiniAppRestoreCoordinator.shared,
            storageKey: MiniAppManagement.defaultStorageKey,
            onStatusChange: { _, _ in WidgetCenter.shared.reloadAllTimelines() }
        )
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
            dataDescription: [original?.dataDescription, "未取込みの共有データ"].compactMap { $0 }.joined(separator: "、")) {
                try await original?.removeData()
                try store.get().removeOwnedData(for: owner)
            }
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
