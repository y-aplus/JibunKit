import Foundation

/// The stable identity supplied by `UISceneSession.persistentIdentifier`.
/// It survives a scene connection being discarded and later restored.
public struct MiniAppWindowSessionID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A window session identifier cannot be empty.")
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) { self.init(rawValue: rawValue) }
}

/// Identifies one live connection of an OS window session. A restored session
/// keeps `sessionID` and receives a new `generation`.
public struct MiniAppWindowConnection: Hashable, Sendable {
    public let sessionID: MiniAppWindowSessionID
    public let generation: UUID

    public init(sessionID: MiniAppWindowSessionID, generation: UUID = UUID()) {
        self.sessionID = sessionID
        self.generation = generation
    }
}

public struct MiniAppWindowSceneSnapshot: Equatable, Sendable {
    public let connection: MiniAppWindowConnection
    public let phase: MiniAppSceneActivity.Phase
    public let selectedID: MiniAppID?

    public init(
        connection: MiniAppWindowConnection,
        phase: MiniAppSceneActivity.Phase,
        selectedID: MiniAppID?
    ) {
        self.connection = connection
        self.phase = phase
        self.selectedID = selectedID
    }
}

/// Process registry for OS window connections. Navigation values and Feature
/// view state stay in each WindowGroup root; the registry only targets it.
@MainActor
public final class MiniAppWindowSceneRegistry {
    public enum Delivery: Equatable, Sendable {
        case delivered(MiniAppWindowConnection)
        case notConnected
        case staleConnection(current: MiniAppWindowConnection?)
    }

    public typealias RouteHandler = @MainActor (MiniAppRoute?) -> Void

    private struct Scene {
        var snapshot: MiniAppWindowSceneSnapshot
        let route: RouteHandler
        var resources: [MiniAppID: [@MainActor () async -> Void]] = [:]
    }

    private var scenes: [MiniAppWindowSessionID: Scene] = [:]

    public init() {}

    /// Connects (or reconnects) one OS session. Reconnection invalidates every
    /// token and scene resource from the previous connection before returning.
    public func connect(
        sessionID: MiniAppWindowSessionID,
        phase: MiniAppSceneActivity.Phase,
        selectedID: MiniAppID?,
        route: @escaping RouteHandler
    ) async -> MiniAppWindowConnection {
        if let previous = scenes.removeValue(forKey: sessionID) {
            await release(previous.resources)
        }
        let connection = MiniAppWindowConnection(sessionID: sessionID)
        scenes[sessionID] = Scene(
            snapshot: .init(connection: connection, phase: phase, selectedID: selectedID),
            route: route
        )
        return connection
    }

    /// Rejects updates from an earlier connection of the same OS session.
    @discardableResult
    public func update(
        _ connection: MiniAppWindowConnection,
        phase: MiniAppSceneActivity.Phase,
        selectedID: MiniAppID?
    ) -> Bool {
        guard var scene = scenes[connection.sessionID], scene.snapshot.connection == connection else {
            return false
        }
        scene.snapshot = .init(connection: connection, phase: phase, selectedID: selectedID)
        scenes[connection.sessionID] = scene
        return true
    }

    public func snapshot(for sessionID: MiniAppWindowSessionID) -> MiniAppWindowSceneSnapshot? {
        scenes[sessionID]?.snapshot
    }

    public var connectedScenes: [MiniAppWindowSceneSnapshot] {
        scenes.values.map(\.snapshot)
    }

    /// Registers a scene-scoped resource. Feature-global work belongs to
    /// `MiniAppRuntime` and must not be registered here.
    @discardableResult
    public func onDisconnect(
        owner: MiniAppID,
        connection: MiniAppWindowConnection,
        _ cleanup: @escaping @MainActor () async -> Void
    ) -> Bool {
        guard owner.isValid,
              var scene = scenes[connection.sessionID],
              scene.snapshot.connection == connection
        else { return false }
        scene.resources[owner, default: []].append(cleanup)
        scenes[connection.sessionID] = scene
        return true
    }

    /// Targets exactly one live connection. Passing an expected generation is
    /// required for callbacks which may outlive the connection that created them.
    @discardableResult
    public func open(
        _ route: MiniAppRoute?,
        in sessionID: MiniAppWindowSessionID,
        expected connection: MiniAppWindowConnection? = nil
    ) -> Delivery {
        guard let scene = scenes[sessionID] else {
            return connection == nil ? .notConnected : .staleConnection(current: nil)
        }
        guard connection == nil || connection == scene.snapshot.connection else {
            return .staleConnection(current: scene.snapshot.connection)
        }
        scene.route(route)
        return .delivered(scene.snapshot.connection)
    }

    /// Ends only this generation. Cleanup is owner-grouped but closing a window
    /// releases all resources in that window and never shuts down global runtimes.
    @discardableResult
    public func disconnect(_ connection: MiniAppWindowConnection) async -> Bool {
        guard let scene = scenes[connection.sessionID], scene.snapshot.connection == connection else {
            return false
        }
        scenes[connection.sessionID] = nil
        await release(scene.resources)
        return true
    }

    private func release(_ resources: [MiniAppID: [@MainActor () async -> Void]]) async {
        for owner in resources.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            for cleanup in (resources[owner] ?? []).reversed() { await cleanup() }
        }
    }
}
