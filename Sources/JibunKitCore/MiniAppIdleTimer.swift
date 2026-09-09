import Foundation
#if os(iOS)
import UIKit
#endif

/// Aggregates cooperative Feature requests for the process-wide idle timer.
@MainActor
public final class MiniAppIdleTimer {
    #if os(iOS)
    public static let shared = MiniAppIdleTimer { UIApplication.shared.isIdleTimerDisabled = $0 }
    #endif

    private var requests: [UUID: MiniAppID] = [:]
    private let apply: @MainActor (Bool) -> Void

    public init(apply: @escaping @MainActor (Bool) -> Void) {
        self.apply = apply
    }

    public var activeOwners: Set<MiniAppID> { Set(requests.values) }

    /// Retain the lease for as long as this operation needs the screen awake.
    /// Multiple operations belonging to the same Feature receive independent leases.
    public func preventSleep(for owner: MiniAppID) -> MiniAppIdleTimerLease {
        precondition(owner.isValid)
        let id = UUID()
        let wasEmpty = requests.isEmpty
        requests[id] = owner
        if wasEmpty { apply(true) }
        return MiniAppIdleTimerLease { [weak self] in self?.release(id) }
    }

    private func release(_ id: UUID) {
        guard requests.removeValue(forKey: id) != nil else { return }
        if requests.isEmpty { apply(false) }
    }
}

@MainActor
public final class MiniAppIdleTimerLease {
    private var cleanup: (@MainActor @Sendable () -> Void)?

    fileprivate init(cleanup: @escaping @MainActor @Sendable () -> Void) {
        self.cleanup = cleanup
    }

    /// Releases synchronously and is safe to call more than once.
    public func release() {
        let action = cleanup
        cleanup = nil
        action?()
    }

    deinit {
        // Deinitialization can occur off the main actor; eventual cleanup is a fallback.
        // Use release() when the end of an operation must immediately update the timer.
        let action = cleanup
        Task { @MainActor in action?() }
    }
}
