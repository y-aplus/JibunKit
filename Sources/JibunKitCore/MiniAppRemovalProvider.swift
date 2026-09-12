/// Feature-owned data deletion. The management layer must stop the owner,
/// unregister its external resources, obtain its exclusive reservation, and
/// confirm with the user before invoking `removeData`.
public struct MiniAppRemovalProvider: Sendable {
    public let id: MiniAppID
    public let dataDescription: String
    public let removeData: @Sendable () async throws -> Void

    public init(
        id: MiniAppID,
        dataDescription: String,
        removeData: @escaping @Sendable () async throws -> Void
    ) {
        self.id = id
        self.dataDescription = dataDescription
        self.removeData = removeData
    }
}
