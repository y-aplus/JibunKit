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

    public init(handlers: [@MainActor (MiniAppHostPhase) -> Void]) {
        self.handlers = handlers
    }

    public func update(_ next: MiniAppHostPhase) {
        guard next != phase else { return }
        phase = next
        for handler in handlers { handler(next) }
    }
}
