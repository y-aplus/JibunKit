import Foundation

/// A Feature's own `NSUserActivity` types (Handoff, Siri suggestions and other
/// continuations). Each type has exactly one owner; the host delivers a
/// continued activity only to that owner's destination.
public struct MiniAppUserActivityHandler {
    public let activityTypes: Set<String>
    /// Must only read the activity. Mutating data or navigating is not allowed.
    public let resolve: @MainActor (NSUserActivity) -> MiniAppURLRouter.Destination?

    public init(activityTypes: Set<String>,
                resolve: @escaping @MainActor (NSUserActivity) -> MiniAppURLRouter.Destination?) {
        self.activityTypes = activityTypes
        self.resolve = resolve
    }
}

public enum MiniAppUserActivityRouter {
    public struct Registration {
        public let id: MiniAppID
        public let handler: MiniAppUserActivityHandler

        public init(id: MiniAppID, handler: MiniAppUserActivityHandler) {
            self.id = id
            self.handler = handler
        }
    }

    public enum Failure: Error, Equatable {
        case invalidType(MiniAppID)
        case reservedType(String)
        case duplicateType(String, [MiniAppID])
    }

    /// Checked when the host builds its registry. `reserved` holds the types the
    /// host itself handles, such as Spotlight's result and query continuation.
    public static func validate(_ registrations: [Registration], reserved: Set<String>) throws {
        var owners: [String: MiniAppID] = [:]
        for registration in registrations {
            for type in registration.handler.activityTypes.sorted() {
                guard !type.isEmpty else { throw Failure.invalidType(registration.id) }
                guard !reserved.contains(type) else { throw Failure.reservedType(type) }
                if let other = owners.updateValue(registration.id, forKey: type) {
                    throw Failure.duplicateType(type, [other, registration.id].sorted { $0.rawValue < $1.rawValue })
                }
            }
        }
    }

    /// Every declared activity type across registrations, for SwiftUI handlers.
    public static func activityTypes(_ registrations: [Registration]) -> [String] {
        Set(registrations.flatMap(\.handler.activityTypes)).sorted()
    }

    @MainActor
    public static func route(for activity: NSUserActivity, registrations: [Registration],
                             registeredIDs: Set<MiniAppID>) -> MiniAppRoute? {
        guard let registration = registrations.first(where: { $0.handler.activityTypes.contains(activity.activityType) }),
              registeredIDs.contains(registration.id),
              let destination = registration.handler.resolve(activity) else { return nil }
        switch destination {
        case .root:
            return MiniAppRoute(id: registration.id, destination: nil)
        case .detail(let identifier):
            guard MiniAppLink.url(for: registration.id, destination: identifier) != nil else { return nil }
            return MiniAppRoute(id: registration.id, destination: identifier)
        }
    }
}
