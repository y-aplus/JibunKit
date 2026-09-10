import Foundation

/// An individually cancellable NotificationCenter registration.
///
/// Cancellation removes the native observer immediately and suppresses values
/// that were extracted before cancellation but are still queued for delivery.
public final class MiniAppNotificationObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var nativeObserver: (any NSObjectProtocol)?
    private var retainedObject: AnyObject?
    private let center: NotificationCenter
    private let deactivate: @Sendable () -> Void

    fileprivate init(
        center: NotificationCenter,
        nativeObserver: any NSObjectProtocol,
        retainedObject: AnyObject?,
        deactivate: @escaping @Sendable () -> Void
    ) {
        self.center = center
        self.nativeObserver = nativeObserver
        self.retainedObject = retainedObject
        self.deactivate = deactivate
    }

    /// Idempotently prevents later delivery and removes the Foundation observer.
    public func cancel() {
        deactivate()
        let observer = lock.withLock { () -> (any NSObjectProtocol)? in
            defer {
                nativeObserver = nil
                retainedObject = nil
            }
            return nativeObserver
        }
        if let observer { center.removeObserver(observer) }
    }

    deinit { cancel() }
}

/// Own one collection per Feature runtime. Registrations in another collection
/// are independent even when they observe the same notification name.
@MainActor
public final class MiniAppNotificationObservations {
    private var observations: [MiniAppNotificationObservation] = []
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

        let delivery = NotificationDeliveryState(receive: receive)
        let nativeObserver = center.addObserver(forName: name, object: object, queue: nil) { [weak delivery] notification in
            guard let delivery, delivery.canExtract(), let value = extract(notification) else { return }
            delivery.enqueue(value)
        }
        let observation = MiniAppNotificationObservation(
            center: center,
            nativeObserver: nativeObserver,
            retainedObject: object,
            deactivate: { delivery.deactivate() }
        )
        observations.append(observation)
        return observation
    }

    /// Cancels only this owner's registrations.
    public func cancelAll() {
        guard !isCancelled else { return }
        isCancelled = true
        let owned = observations
        observations.removeAll()
        for observation in owned { observation.cancel() }
    }

    deinit {
        for observation in observations { observation.cancel() }
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
        lock.withLock {
            active = false
            receive = nil
        }
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
