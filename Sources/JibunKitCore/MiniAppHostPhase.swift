/// Aggregate host activity, not whether an individual Feature's view is visible.
public enum MiniAppHostPhase: Sendable, Equatable {
    case active, inactive, background
}

/// Delivers host transitions to every registered Integration, including Features
/// whose views have never been created. Handlers must return promptly; this does
/// not grant background execution time or make blocking work safe.
@MainActor
public final class MiniAppLifecycleDispatcher {
    private let handlers: [@MainActor (MiniAppHostPhase) -> Void]
    private var phase: MiniAppHostPhase?
    private var pending: [MiniAppHostPhase] = []
    private var delivering = false

    public init(handlers: [@MainActor (MiniAppHostPhase) -> Void]) {
        self.handlers = handlers
    }

    public func update(_ next: MiniAppHostPhase) {
        guard next != (pending.last ?? phase) else { return }
        pending.append(next)
        guard !delivering else { return }
        delivering = true
        defer { delivering = false }
        while !pending.isEmpty {
            let current = pending.removeFirst()
            phase = current
            // Complete delivery to every owner before a handler-triggered update.
            for handler in handlers { handler(current) }
        }
    }
}
