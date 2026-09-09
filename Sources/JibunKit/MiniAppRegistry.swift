#if os(iOS)
import CounterIntegration
import JibunKitCore
import ReminderIntegration

@MainActor
enum MiniAppRegistry {
    static let all = makeRegistry([
        CounterMiniApp.definition,
        ReminderMiniApp.definition,
        RecordsMiniApp.definition,
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
