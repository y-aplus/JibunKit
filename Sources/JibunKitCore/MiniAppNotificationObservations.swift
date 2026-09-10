import Foundation

/// An individually cancellable NotificationCenter registration.
///
/// Cancellation removes the native observer immediately. Owner cancellation on
/// the main actor suppresses values still queued for main-actor delivery.
public final class MiniAppNotificationObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var nativeObserver: (any NSObjectProtocol)?
    private var retainedObject: AnyObject?
    private let center: NotificationCenter
    private let deactivate: @Sendable () -> Void
    private let removeFromOwner: @Sendable () -> Void

    fileprivate init(
        center: NotificationCenter,
        nativeObserver: any NSObjectProtocol,
        retainedObject: AnyObject?,
        deactivate: @escaping @Sendable () -> Void,
        removeFromOwner: @escaping @Sendable () -> Void
    ) {
        self.center = center
        self.nativeObserver = nativeObserver
        self.retainedObject = retainedObject
        self.deactivate = deactivate
        self.removeFromOwner = removeFromOwner
    }

    /// Idempotently deactivates delivery and removes the Foundation observer.
    public func cancel() {
        deactivate()
        let removed = lock.withLock { () -> ((any NSObjectProtocol)?, AnyObject?) in
            let removed = (nativeObserver, retainedObject)
            nativeObserver = nil
            retainedObject = nil
            return removed
        }
        if let observer = removed.0 { center.removeObserver(observer) }
        removeFromOwner()
        withExtendedLifetime(removed.1) {}
    }

    deinit { cancel() }
}

/// Own one collection per Feature runtime. Registrations in another collection
/// are independent even when they observe the same notification name.
@MainActor
public final class MiniAppNotificationObservations {
    private let registry = NotificationObservationRegistry()
    public private(set) var isCancelled = false

    public init() {}

    /// Uses NotificationCenter's native name and sender filtering. The extractor
    /// runs on the posting thread and must return a Sendable value before delivery
    /// crosses to the main actor.
    @discardableResult
    public func observe<Value: Sendable>(
        center: NotificationCenter = .default,
        name: Notification.Name,
        object: AnyObject? = nil,
        extract: @escaping @Sendable (Notification) -> Value?,
        receive: @escaping @MainActor @Sendable (Value) -> Void
    ) throws -> MiniAppNotificationObservation {
        guard !isCancelled else { throw MiniAppRuntime.Failure.closed }

        let id = UUID()
        let delivery = NotificationDeliveryState(receive: receive)
        let nativeObserver = center.addObserver(forName: name, object: object, queue: nil) { [weak delivery] notification in
            guard let delivery, delivery.canExtract(), let value = extract(notification) else { return }
            delivery.enqueue(value)
        }
        let observation = MiniAppNotificationObservation(
            center: center,
            nativeObserver: nativeObserver,
            retainedObject: object,
            deactivate: { delivery.deactivate() },
            removeFromOwner: { [weak registry] in registry?.remove(id: id) }
        )
        registry.insert(observation, id: id)
        return observation
    }

    /// Cancels only this owner's registrations.
    public func cancelAll() {
        guard !isCancelled else { return }
        isCancelled = true
        let owned = registry.removeAll()
        for observation in owned { observation.cancel() }
    }

    deinit {
        for observation in registry.removeAll() { observation.cancel() }
    }
}

private final class NotificationObservationRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var observations: [UUID: MiniAppNotificationObservation] = [:]

    func insert(_ observation: MiniAppNotificationObservation, id: UUID) {
        lock.withLock { observations[id] = observation }
    }

    func remove(id: UUID) {
        let removed = lock.withLock { observations.removeValue(forKey: id) }
        withExtendedLifetime(removed) {}
    }

    func removeAll() -> [MiniAppNotificationObservation] {
        lock.withLock {
            defer { observations.removeAll() }
            return Array(observations.values)
        }
    }
}

private final class NotificationDeliveryState<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var receive: (@MainActor @Sendable (Value) -> Void)?

    init(receive: @escaping @MainActor @Sendable (Value) -> Void) {
        self.receive = receive
    }

    func canExtract() -> Bool { lock.withLock { active } }
    func deactivate() {
        let removedReceive = lock.withLock { () -> (@MainActor @Sendable (Value) -> Void)? in
            active = false
            let removedReceive = receive
            receive = nil
            return removedReceive
        }
        withExtendedLifetime(removedReceive) {}
    }

    func enqueue(_ value: Value) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let receive = self.lock.withLock { () -> (@MainActor @Sendable (Value) -> Void)? in
                guard self.active else { return nil }
                return self.receive
            }
            receive?(value)
        }
    }
}
