#if os(iOS)
import AppIntents
import Foundation
import JibunKitCore

/// iOS sees JibunKit as one app, so its Focus settings cannot pick Features.
/// This filter lets each Focus choose the mini apps it shows; the host applies
/// the choice through `MiniAppRegistry.applyFocus`.
struct JibunKitFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Show Mini Apps"
    static let description = IntentDescription("Choose the mini apps this Focus shows. The others leave the list, quick actions and icon badge, and their notifications are silenced.")

    @Parameter(title: "Mini Apps")
    var miniApps: [MiniAppEntity]?

    var displayRepresentation: DisplayRepresentation {
        guard let miniApps, !miniApps.isEmpty else { return DisplayRepresentation(title: "All mini apps") }
        let titles = miniApps.map(\.title).formatted(.list(type: .and))
        return DisplayRepresentation(title: "\(titles)")
    }

    /// nil, or an empty choice, shows every Feature.
    var shownIDs: Set<MiniAppID>? {
        guard let miniApps, !miniApps.isEmpty else { return nil }
        return Set(miniApps.map { MiniAppID($0.id) })
    }

    /// Features set their ID as the notification's `filterCriteria`.
    var appContext: FocusFilterAppContext {
        FocusFilterAppContext(notificationFilterPredicate: shownIDs.map {
            NSPredicate(format: "SELF IN %@", $0.map(\.rawValue))
        })
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        MiniAppRegistry.applyFocus(shownIDs)
        return .result()
    }
}

/// A Feature as the Focus filter offers it.
struct MiniAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mini App"
    static let defaultQuery = MiniAppEntityQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    @MainActor
    init(_ definition: MiniAppDefinition) {
        id = definition.id.rawValue
        title = definition.title
    }
}

struct MiniAppEntityQuery: EntityQuery {
    /// A Feature that is no longer registered drops out of a saved choice.
    @MainActor
    func entities(for identifiers: [String]) async throws -> [MiniAppEntity] {
        identifiers.compactMap { id in MiniAppRegistry.all.first { $0.id.rawValue == id }.map(MiniAppEntity.init) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MiniAppEntity] {
        MiniAppRegistry.enabled.map(MiniAppEntity.init)
    }
}
#endif
