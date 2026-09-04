#if os(iOS)
import CounterFeature
import JibunKitCore
import ReminderFeature
import SwiftUI

struct MiniAppDescriptor: Identifiable {
    let id: MiniAppID
    let title: String
    let systemImage: String
    private let destination: @MainActor (MiniAppContext) -> AnyView

    init<Destination: View>(
        id: MiniAppID,
        title: String,
        systemImage: String,
        destination: @escaping @MainActor (MiniAppContext) -> Destination
    ) {
        precondition(id.isValid, "Mini-app IDs must start with a-z and contain only a-z, 0-9, '.', '-', or '_'.")
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.destination = { context in
            AnyView(destination(context))
        }
    }

    @MainActor
    func makeDestination() -> AnyView {
        destination(MiniAppContext(id: id))
    }
}

@MainActor
enum MiniAppRegistry {
    static let all = makeRegistry([
        MiniAppDescriptor(
            id: .counter,
            title: "カウンター",
            systemImage: "number"
        ) { context in
            CounterRootView(context: context)
        },
        MiniAppDescriptor(
            id: .reminder,
            title: "リマインダー",
            systemImage: "bell"
        ) { context in
            ReminderRootView(context: context)
        },
    ])

    static let registeredIDs = Set(all.map(\.id))

    static func descriptor(for id: MiniAppID) -> MiniAppDescriptor? {
        all.first { $0.id == id }
    }

    private static func makeRegistry(
        _ miniApps: [MiniAppDescriptor]
    ) -> [MiniAppDescriptor] {
        precondition(
            Set(miniApps.map(\.id)).count == miniApps.count,
            "Mini-app IDs must be unique."
        )
        return miniApps
    }
}
#endif
