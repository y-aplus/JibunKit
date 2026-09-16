#if canImport(AlarmKit) && canImport(AppIntents)
import AlarmKit
import AppIntents
import Foundation
import JibunKitCore
import SwiftUI

public protocol FixtureAlarmFeature: Sendable {
    associatedtype Metadata: AlarmMetadata
    static var owner: MiniAppID { get }
    static var title: String { get }
    static var tint: Color { get }
    static func metadata(_ identity: MiniAppContinuingIdentity) -> Metadata
}

public struct FeatureAAlarmMetadata: AlarmMetadata {
    public let owner: String
    public let localID: String
    public let generation: UUID
    public let registrationID: UUID
    public let reason: String
}

public struct FeatureBAlarmMetadata: AlarmMetadata {
    public let owner: String
    public let localID: String
    public let generation: UUID
    public let registrationID: UUID
    public let routine: String
}

public enum FeatureAAlarm: FixtureAlarmFeature {
    public static let owner = MiniAppID("alarm-feature-a")
    public static let title = "A: 集中を終える"
    public static let tint = Color.orange
    public static func metadata(_ identity: MiniAppContinuingIdentity) -> FeatureAAlarmMetadata {
        .init(owner: identity.owner, localID: identity.localID, generation: identity.generation,
              registrationID: identity.registrationID, reason: "集中セッション")
    }
}

public enum FeatureBAlarm: FixtureAlarmFeature {
    public static let owner = MiniAppID("alarm-feature-b")
    public static let title = "B: 服薬を確認"
    public static let tint = Color.blue
    public static func metadata(_ identity: MiniAppContinuingIdentity) -> FeatureBAlarmMetadata {
        .init(owner: identity.owner, localID: identity.localID, generation: identity.generation,
              registrationID: identity.registrationID, routine: "夜の服薬")
    }
}

public enum FixtureAlarmSchedule: Sendable {
    case fixed(Date)
    case relative(hour: Int, minute: Int, weekdays: [Locale.Weekday])
    case immediateCountdown(seconds: TimeInterval)
}

@available(iOS 26.0, *)
public enum FixtureAlarmConfiguration {
    public static func make<F: FixtureAlarmFeature>(
        feature: F.Type, identity: MiniAppContinuingIdentity, schedule: FixtureAlarmSchedule,
        stopIntent: any LiveActivityIntent
    ) -> AlarmManager.AlarmConfiguration<F.Metadata> {
        let stop = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.circle")
        let alert = AlarmPresentation.Alert(title: F.title, stopButton: stop)
        let metadata = F.metadata(identity)
        switch schedule {
        case .fixed(let date):
            let attributes = AlarmAttributes(presentation: .init(alert: alert), metadata: metadata, tintColor: F.tint)
            return .init(schedule: .fixed(date), attributes: attributes, stopIntent: stopIntent)
        case .relative(let hour, let minute, let weekdays):
            let recurrence: Alarm.Schedule.Relative.Recurrence = weekdays.isEmpty ? .never : .weekly(weekdays)
            let nativeSchedule = Alarm.Schedule.relative(.init(time: .init(hour: hour, minute: minute), repeats: recurrence))
            let attributes = AlarmAttributes(presentation: .init(alert: alert), metadata: metadata, tintColor: F.tint)
            return .init(schedule: nativeSchedule, attributes: attributes, stopIntent: stopIntent)
        case .immediateCountdown(let seconds):
            let pause = AlarmButton(text: "一時停止", textColor: .white, systemImageName: "pause.circle")
            let resume = AlarmButton(text: "再開", textColor: .white, systemImageName: "play.circle")
            let presentation = AlarmPresentation(
                alert: alert,
                countdown: .init(title: F.title, pauseButton: pause),
                paused: .init(title: "一時停止中", resumeButton: resume))
            let attributes = AlarmAttributes(presentation: presentation, metadata: metadata, tintColor: F.tint)
            return .init(countdownDuration: .init(preAlert: seconds, postAlert: seconds), schedule: nil,
                         attributes: attributes, stopIntent: stopIntent)
        }
    }
}

public actor FixtureAlarmAdmission {
    public private(set) var generation = UUID()
    public private(set) var accepting = true
    public private(set) var stopEvents = 0

    public func validate(localID: String, generation expected: UUID) throws {
        guard accepting else { throw MiniAppContinuingError.admissionClosed }
        guard expected == generation else { throw MiniAppAlarmError.staleGeneration }
        guard localID == "same-id" else { throw MiniAppAlarmError.missingRegistration }
    }
    public func close() { accepting = false }
    public func open() { accepting = true }
    public func resetBusinessData() { generation = UUID(); stopEvents = 0 }
    public func recordSystemStop() { stopEvents += 1 }
}

@available(iOS 26.0, *)
public actor FixtureAlarmRuntime<F: FixtureAlarmFeature> {
    public typealias Native = MiniAppAlarmKitNative<F.Metadata>
    public static var sameLocalID: String { "same-id" }
    public let admission = FixtureAlarmAdmission()
    private var coordinator: MiniAppAlarmCoordinator<Native>?
    private var currentIdentity: MiniAppContinuingIdentity?
    public private(set) var message = "未登録"

    public init() {}

    public func configure(containerURL: URL) throws {
        guard coordinator == nil else { return }
        let journal = try MiniAppContinuingJournal(owner: F.owner, namespace: "alarmkit", containerURL: containerURL)
        let admission = self.admission
        coordinator = .init(owner: F.owner, native: .init(), store: MiniAppAlarmJournalStore(journal: journal)) {
            try await admission.validate(localID: $0, generation: $1)
        }
    }

    public func schedule(_ schedule: FixtureAlarmSchedule) async {
        do {
            let coordinator = try service()
            let generation = await admission.generation
            let identity = try await coordinator.schedule(localID: Self.sameLocalID, generation: generation) { identity, systemID in
                FixtureAlarmConfiguration.make(feature: F.self, identity: identity, schedule: schedule,
                    stopIntent: FixtureAlarmStopIntent(owner: identity.owner, localID: identity.localID,
                        generation: identity.generation, registrationID: identity.registrationID, systemID: systemID))
            }
            currentIdentity = identity
            message = "登録済み \(identity.registrationID.uuidString.prefix(8))"
        } catch { message = "失敗: \(error)" }
    }

    public func requestAuthorization() async {
        do {
            let state = try await MiniAppAlarmKitAuthorization().request()
            message = "OS許可: \(state.rawValue)（app全体）"
        } catch { message = "OS許可失敗: \(error)" }
    }

    public func perform(_ action: MiniAppAlarmAction) async {
        do {
            guard let identity = currentIdentity else { throw MiniAppAlarmError.missingRegistration }
            try await service().perform(action, identity: identity)
            if action == .cancel { currentIdentity = nil }
            message = "\(action.rawValue) 反映確認済み"
        } catch { message = "失敗: \(error)" }
    }

    public func reconcile() async {
        do {
            let result = try await service().reconcile()
            message = "照合 active=\(result.active.count) missing=\(result.missing.count) unknown=\(result.unknownSystemIDs.count)"
        } catch { message = "照合失敗: \(error)" }
    }

    public func resetFeatureOnly() async {
        await admission.resetBusinessData()
        currentIdentity = nil
        message = "業務世代を更新（OS登録は照合対象として保持）"
    }

    public func surface() throws -> MiniAppContinuingSurface { try service().surface() }

    public func handleSystemStop(_ identity: MiniAppContinuingIdentity, systemID: UUID) async throws {
        try await service().handleSystemIntent(identity: identity, systemID: systemID) { [admission] in
            await admission.recordSystemStop()
        }
    }

    private func service() throws -> MiniAppAlarmCoordinator<Native> {
        guard let coordinator else { throw MiniAppAlarmError.missingRegistration }
        return coordinator
    }
}

@available(iOS 26.0, *) public let featureAAlarmRuntime = FixtureAlarmRuntime<FeatureAAlarm>()
@available(iOS 26.0, *) public let featureBAlarmRuntime = FixtureAlarmRuntime<FeatureBAlarm>()

@available(iOS 26.0, *)
public struct FixtureAlarmStopIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "アラーム停止をFeatureへ記録"
    public static let openAppWhenRun = false
    @Parameter(title: "Owner") public var owner: String
    @Parameter(title: "Local ID") public var localID: String
    @Parameter(title: "Generation") public var generation: String
    @Parameter(title: "Registration ID") public var registrationID: String
    @Parameter(title: "System ID") public var systemID: String

    public init() { owner = ""; localID = ""; generation = ""; registrationID = ""; systemID = "" }
    public init(owner: String, localID: String, generation: UUID, registrationID: UUID, systemID: UUID) {
        self.owner = owner; self.localID = localID
        self.generation = generation.uuidString; self.registrationID = registrationID.uuidString
        self.systemID = systemID.uuidString
    }

    public func perform() async throws -> some IntentResult {
        guard let generation = UUID(uuidString: generation), let registrationID = UUID(uuidString: registrationID),
              let systemID = UUID(uuidString: systemID) else {
            throw MiniAppAlarmError.staleRegistration
        }
        let id = try MiniAppContinuingIdentity(owner: MiniAppID(owner), localID: localID,
                                               generation: generation, registrationID: registrationID)
        // AlarmKit performs the standard stop itself. The current daemon ID is
        // deliberately resolved from the exact journal record by the coordinator.
        if owner == FeatureAAlarm.owner.rawValue {
            try await featureAAlarmRuntime.handleSystemStop(id, systemID: systemID)
        } else if owner == FeatureBAlarm.owner.rawValue {
            try await featureBAlarmRuntime.handleSystemStop(id, systemID: systemID)
        } else { throw MiniAppAlarmError.wrongOwner }
        return .result()
    }
}

public struct ContinuingAlarmIntents: AppIntentsPackage {}
#endif
