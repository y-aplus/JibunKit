import Foundation

/// Coordinates restores across scenes in one process. Feature stores still own
/// coordination with ordinary writes and extensions in other processes.
public actor MiniAppRestoreCoordinator {
    public static let shared = MiniAppRestoreCoordinator()

    public struct Conflict: Error, Sendable {
        public let owners: Set<MiniAppID>
    }

    private var active: Set<MiniAppID> = []

    public init() {}

    func perform(ids: [MiniAppID], operation: @Sendable () async throws -> Void) async throws {
        try Task.checkCancellation()
        let requested = Set(ids)
        let conflicts = active.intersection(requested)
        guard conflicts.isEmpty else { throw Conflict(owners: conflicts) }
        active.formUnion(requested)
        defer { active.subtract(requested) }
        try await operation()
    }
}
