#if os(iOS) && canImport(AlarmKit) && canImport(AppIntents)
import AlarmKit
import AppIntents
import Foundation

/// Build the SDK configuration at the native request site. AlarmConfiguration
/// itself does not promise Sendable; immutable Feature inputs/factory do.
@available(iOS 26.0, *)
public struct MiniAppAlarmKitConfiguration<Metadata: AlarmMetadata>: Sendable {
    fileprivate let make: @Sendable () throws -> AlarmManager.AlarmConfiguration<Metadata>
    public init(_ make: @escaping @Sendable () throws -> AlarmManager.AlarmConfiguration<Metadata>) {
        self.make = make
    }
}

@available(iOS 26.0, *)
public struct MiniAppAlarmKitNative<Metadata: AlarmMetadata>: MiniAppAlarmNative {
    public typealias Configuration = MiniAppAlarmKitConfiguration<Metadata>

    public init() {}

    public func schedule(id: UUID, configuration: Configuration) async throws {
        _ = try await AlarmManager.shared.schedule(id: id, configuration: try configuration.make())
    }

    public func perform(_ action: MiniAppAlarmAction, id: UUID) async throws {
        switch action {
        case .stop: try AlarmManager.shared.stop(id: id)
        case .cancel: try AlarmManager.shared.cancel(id: id)
        case .countdown: try AlarmManager.shared.countdown(id: id)
        case .pause: try AlarmManager.shared.pause(id: id)
        case .resume: try AlarmManager.shared.resume(id: id)
        }
    }

    public func snapshots() async throws -> [MiniAppAlarmSnapshot] {
        try AlarmManager.shared.alarms.map { alarm in
            let state: MiniAppAlarmState = switch alarm.state {
            case .scheduled: .scheduled
            case .countdown: .countdown
            case .paused: .paused
            case .alerting: .alerting
            @unknown default: .unknown
            }
            return .init(id: alarm.id, state: state)
        }
    }

    public func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await _ in AlarmManager.shared.alarmUpdates {
                    guard !Task.isCancelled else { break }
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@available(iOS 26.0, *)
public struct MiniAppAlarmKitAuthorization: MiniAppAlarmAuthorizationClient {
    public init() {}

    public func state() async -> MiniAppAlarmAuthorizationState {
        map(AlarmManager.shared.authorizationState)
    }

    public func request() async throws -> MiniAppAlarmAuthorizationState {
        map(try await AlarmManager.shared.requestAuthorization())
    }

    private func map(_ state: AlarmManager.AuthorizationState) -> MiniAppAlarmAuthorizationState {
        switch state {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .denied
        }
    }
}
#endif
