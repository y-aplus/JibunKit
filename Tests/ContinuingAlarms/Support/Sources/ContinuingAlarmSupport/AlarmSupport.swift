#if os(iOS)
import AlarmKit
import AppIntents
import Foundation
import JibunKitCore
import SwiftUI

public enum ContinuingAlarmSchedule: Sendable {
    case fixed(Date)
    case relative(hour: Int, minute: Int, weekdays: [Locale.Weekday])
    case immediateCountdown(seconds: TimeInterval)
}

public protocol ContinuingAlarmFixtureFeature: Sendable {
    associatedtype Metadata: AlarmMetadata
    associatedtype BusinessState: Codable, Sendable
    static var owner: MiniAppID { get }
    static var localID: String { get }
    static var title: LocalizedStringResource { get }
    static var tint: Color { get }
    static var initialState: BusinessState { get }
    static func metadata(identity: MiniAppContinuingIdentity) -> Metadata
    static func summary(_ state: BusinessState) -> String
    static func recordSystemStop(_ state: inout BusinessState)
}

@available(iOS 26.0, *)
public enum ContinuingAlarmConfiguration {
    public static func make<F: ContinuingAlarmFixtureFeature>(
        feature: F.Type, identity: MiniAppContinuingIdentity, schedule: ContinuingAlarmSchedule,
        stopIntent: any LiveActivityIntent
    ) -> AlarmManager.AlarmConfiguration<F.Metadata> {
        let stop = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.circle")
        let alert = AlarmPresentation.Alert(title: F.title, stopButton: stop)
        let metadata = F.metadata(identity: identity)
        switch schedule {
        case .fixed(let date):
            return .init(countdownDuration: nil, schedule: .fixed(date),
                attributes: .init(presentation: .init(alert: alert), metadata: metadata, tintColor: F.tint),
                stopIntent: stopIntent)
        case .relative(let hour, let minute, let weekdays):
            let recurrence: Alarm.Schedule.Relative.Recurrence = weekdays.isEmpty ? .never : .weekly(weekdays)
            let alarmSchedule = Alarm.Schedule.relative(.init(time: .init(hour: hour, minute: minute),
                                                               repeats: recurrence))
            return .init(countdownDuration: nil, schedule: alarmSchedule,
                attributes: .init(presentation: .init(alert: alert), metadata: metadata, tintColor: F.tint),
                stopIntent: stopIntent)
        case .immediateCountdown(let seconds):
            let pause = AlarmButton(text: "一時停止", textColor: .white, systemImageName: "pause.circle")
            let resume = AlarmButton(text: "再開", textColor: .white, systemImageName: "play.circle")
            let presentation = AlarmPresentation(alert: alert,
                countdown: .init(title: F.title, pauseButton: pause),
                paused: .init(title: "一時停止中", resumeButton: resume))
            return .init(countdownDuration: .init(preAlert: seconds, postAlert: seconds), schedule: nil,
                attributes: .init(presentation: presentation, metadata: metadata, tintColor: F.tint),
                stopIntent: stopIntent)
        }
    }
}

@available(iOS 26.0, *)
public final class ContinuingAlarmFeatureService<F: ContinuingAlarmFixtureFeature>: Sendable {
    public typealias Native = MiniAppAlarmKitNative<F.Metadata>
    public let store: MiniAppSharedState<F.BusinessState>
    private let coordinator: MiniAppAlarmCoordinator<Native>
    private let statusLock = NSLock()
    private nonisolated(unsafe) var statusValue = "未登録"

    public init(store: MiniAppSharedState<F.BusinessState>, journal: MiniAppContinuingJournal) {
        self.store = store
        coordinator = MiniAppAlarmCoordinator(owner: F.owner, native: .init(),
            store: MiniAppAlarmJournalStore(journal: journal)) { localID, generation in
                let snapshot = try store.read()
                guard localID == F.localID, generation == snapshot.generation else {
                    throw MiniAppAlarmError.staleGeneration
                }
            }
    }

    public func status() -> String { statusLock.withLock { statusValue } }

    public func current() async throws -> MiniAppAlarmRegistrationDescriptor? {
        let snapshot = try store.read()
        return try await coordinator.current(localID: F.localID, generation: snapshot.generation)
    }

    @discardableResult
    public func schedule(_ schedule: ContinuingAlarmSchedule,
                         stopIntent: @escaping @Sendable (MiniAppContinuingIdentity, UUID) -> any LiveActivityIntent)
        async throws -> MiniAppAlarmRegistrationDescriptor {
        let snapshot = try store.read()
        if let existing = try await coordinator.current(localID: F.localID, generation: snapshot.generation) {
            setStatus("既存登録を再利用 \(existing.systemID.uuidString.prefix(8))")
            return existing
        }
        let identity = try await coordinator.schedule(localID: F.localID, generation: snapshot.generation) { identity, id in
            ContinuingAlarmConfiguration.make(feature: F.self, identity: identity, schedule: schedule,
                                               stopIntent: stopIntent(identity, id))
        }
        let result = try await requiredCurrent(identity)
        setStatus("登録済み \(result.systemID.uuidString.prefix(8))")
        return result
    }

    public func retryPending(_ identity: MiniAppContinuingIdentity, schedule: ContinuingAlarmSchedule,
                             stopIntent: @escaping @Sendable (MiniAppContinuingIdentity, UUID) -> any LiveActivityIntent)
        async throws {
        try await coordinator.retryPending(identity) { identity, id in
            ContinuingAlarmConfiguration.make(feature: F.self, identity: identity, schedule: schedule,
                                               stopIntent: stopIntent(identity, id))
        }
        setStatus("pendingを再試行")
    }

    public func perform(_ action: MiniAppAlarmAction) async throws {
        guard let descriptor = try await current() else { throw MiniAppAlarmError.missingRegistration }
        try await coordinator.perform(action, identity: descriptor.identity)
        setStatus("\(action.rawValue) 反映確認済み")
    }

    public func handleSystemStop(identity: MiniAppContinuingIdentity, systemID: UUID) async throws {
        try await coordinator.handleSystemIntent(identity: identity, systemID: systemID) { [store] in
            try store.update(generation: identity.generation) { F.recordSystemStop(&$0) }
        }
        setStatus("OS標準停止callbackを記録")
    }

    public func resetFeatureOnly() throws {
        let snapshot = try store.read()
        try store.update(generation: snapshot.generation) { $0 = F.initialState }
        setStatus("このFeatureだけreset")
    }

    public func reconcile() async throws -> MiniAppAlarmReconciliation {
        let result = try await coordinator.reconcile()
        setStatus("照合 active=\(result.active.count) missing=\(result.missing.count) unknown=\(result.unknownSystemIDs.count)")
        return result
    }

    public func observeAfterDurableRead() async throws {
        _ = try store.read()
        try await coordinator.observe()
    }

    public func surface() -> MiniAppContinuingSurface { coordinator.surface(id: "alarmkit") }

    private func requiredCurrent(_ identity: MiniAppContinuingIdentity) async throws
        -> MiniAppAlarmRegistrationDescriptor {
        let snapshot = try store.read()
        guard let value = try await coordinator.current(localID: F.localID, generation: snapshot.generation),
              value.identity == identity else { throw MiniAppAlarmError.missingRegistration }
        return value
    }

    private func setStatus(_ value: String) { statusLock.withLock { statusValue = value } }
}
#endif
