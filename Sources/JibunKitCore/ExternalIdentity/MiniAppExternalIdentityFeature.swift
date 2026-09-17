import Foundation

/// Standard Feature wiring: runtime stop closes external admission and management
/// removal deletes only this owner's CloudKit zone.
@MainActor
public final class MiniAppExternalIdentityFeature {
    public let id: MiniAppID
    public let coordinator: MiniAppExternalIdentityCoordinator
    public lazy var lifetime = MiniAppFeatureLifetime(id: id) { [coordinator] runtime in
        try await coordinator.connect(to: runtime)
    }
    public lazy var removal = MiniAppRemovalProvider(
        id: id,
        dataDescription: "このFeatureが所有する外部account data",
        removeData: { [coordinator] in try await coordinator.removeOwnedData() }
    )

    public init(id: MiniAppID, container: MiniAppExternalContainer,
                backend: any MiniAppExternalIdentityBackend) {
        self.id = id
        coordinator = MiniAppExternalIdentityCoordinator(owner: id, container: container, backend: backend)
    }
}
