import Foundation

/// Resolves navigation addresses without running Feature operations.
public enum MiniAppURLRouter {
    public enum Destination: Equatable, Sendable {
        case root
        case detail(String)
    }

    /// Must only parse/validate the URL. All registrations may be consulted to
    /// detect ambiguity, so a resolver must not mutate data or navigate.
    public typealias Resolver = @MainActor (URL) -> Destination?

    public struct Registration {
        public let id: MiniAppID
        public let resolve: Resolver

        public init(id: MiniAppID, resolve: @escaping Resolver) {
            self.id = id
            self.resolve = resolve
        }
    }

    public enum Failure: Error, Equatable {
        case invalidOwner(MiniAppID)
        case duplicateOwner(MiniAppID)
        case ambiguousOwners([MiniAppID])
    }

    /// A unique match can only address its own Feature. The host applies the
    /// returned route in the scene to which SwiftUI delivered the original URL.
    @MainActor
    public static func resolve(_ url: URL, registrations: [Registration]) throws -> MiniAppRoute? {
        var owners: Set<MiniAppID> = []
        for registration in registrations {
            guard registration.id.isValid else { throw Failure.invalidOwner(registration.id) }
            guard owners.insert(registration.id).inserted else { throw Failure.duplicateOwner(registration.id) }
        }
        // Preserve the existing host-owned URL contract, including malformed
        // host URLs: Feature resolvers must not reinterpret them as commands.
        guard let scheme = url.scheme, scheme.lowercased() != "jibunkit" else { return nil }
        var matches: [MiniAppRoute] = []
        for registration in registrations {
            guard let destination = registration.resolve(url) else { continue }
            let value: String?
            switch destination {
            case .root: value = nil
            case .detail(let identifier): value = identifier
            }
            matches.append(MiniAppRoute(id: registration.id, destination: value))
        }
        guard matches.count <= 1 else {
            throw Failure.ambiguousOwners(matches.map(\.id).sorted { $0.rawValue < $1.rawValue })
        }
        return matches.first
    }
}
