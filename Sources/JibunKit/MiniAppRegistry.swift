#if os(iOS)
import CounterIntegration
import JibunKitCore
import ReminderIntegration
import Foundation
import CoreSpotlight

@MainActor
enum MiniAppRegistry {
    static let all = makeRegistry([
        CounterMiniApp.definition,
        ReminderMiniApp.definition,
    ])

    static let consents = MiniAppConsentStore(defaults: .standard)
    static let management = MiniAppManagement(
        registrations: all.map { definition in
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
        }, defaults: .standard, consents: consents
    )

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
