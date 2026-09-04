#if os(iOS)
import CounterFeature
import JibunKitCore
import ReminderFeature
import ZaikoFeature

@MainActor
enum MiniAppRegistry {
    static let all = makeRegistry([
        CounterMiniApp.definition,
        ReminderMiniApp.definition,
        ZaikoMiniApp.definition,
    ])

    static let registeredIDs = Set(all.map(\.id))

    static func definition(for id: MiniAppID) -> MiniAppDefinition? {
        all.first { $0.id == id }
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
