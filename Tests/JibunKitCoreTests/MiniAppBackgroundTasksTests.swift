import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppBackgroundTasksTests: XCTestCase {
    func testTwoOwnersRegisterAndReceiveOnlyTheirNativeLaunches() throws {
        let scheduler = BackgroundTaskSchedulerSpy()
        let center = MiniAppBackgroundTaskCenter(scheduler: scheduler)
        let a = center.tasks(for: context("feature-a"))
        let b = center.tasks(for: context("feature-b"))
        var launches: [String] = []

        try a.register(identifier: "com.example.a.refresh", kind: .appRefresh) { task in
            launches.append("a:\(task.identifier)")
        }
        try b.register(
            identifier: "com.example.b.processing",
            kind: .processing
        ) { task in
            launches.append("b:\(task.identifier)")
        }

        scheduler.launch("com.example.b.processing")
        XCTAssertEqual(launches, ["b:com.example.b.processing"])
        scheduler.launch("com.example.a.refresh")
        XCTAssertEqual(launches, ["b:com.example.b.processing", "a:com.example.a.refresh"])
    }

    func testSubmitPreservesStandardRequestKindsAndRejectsAnotherOwner() throws {
        let scheduler = BackgroundTaskSchedulerSpy()
        let center = MiniAppBackgroundTaskCenter(scheduler: scheduler)
        let a = center.tasks(for: context("feature-a"))
        let b = center.tasks(for: context("feature-b"))
        let date = Date(timeIntervalSince1970: 123)
        try a.register(identifier: "com.example.a.refresh", kind: .appRefresh) { _ in }
        try a.register(
            identifier: "com.example.a.processing",
            kind: .processing
        ) { _ in }

        try a.submit(.init(identifier: "com.example.a.refresh", earliestBeginDate: date))
        try a.submit(.init(
            identifier: "com.example.a.processing",
            requiresNetworkConnectivity: true,
            requiresExternalPower: true
        ))
        try a.submit(.init(
            identifier: "com.example.a.processing",
            requiresNetworkConnectivity: false,
            requiresExternalPower: false
        ))

        XCTAssertEqual(scheduler.submissions.map(\.request), [
            .init(identifier: "com.example.a.refresh", earliestBeginDate: date),
            .init(identifier: "com.example.a.processing", requiresNetworkConnectivity: true,
                  requiresExternalPower: true),
            .init(identifier: "com.example.a.processing", requiresNetworkConnectivity: false,
                  requiresExternalPower: false),
        ])
        XCTAssertEqual(scheduler.submissions.map(\.kind), [
            .appRefresh,
            .processing,
            .processing,
        ])
        XCTAssertThrowsError(try b.submit(.init(identifier: "com.example.a.refresh"))) {
            XCTAssertEqual($0 as? MiniAppBackgroundTaskCenter.Failure, .identifierNotOwned)
        }
    }

    func testOwnerCancellationCannotCancelAnotherOwnersPendingRequests() throws {
        let scheduler = BackgroundTaskSchedulerSpy()
        let center = MiniAppBackgroundTaskCenter(scheduler: scheduler)
        let a = center.tasks(for: context("feature-a"))
        let b = center.tasks(for: context("feature-b"))
        try a.register(identifier: "com.example.a.refresh", kind: .appRefresh) { _ in }
        try a.register(identifier: "com.example.a.processing", kind: .processing) { _ in }
        try b.register(identifier: "com.example.b.refresh", kind: .appRefresh) { _ in }

        a.cancelAllPendingRequests()
        XCTAssertEqual(Set(scheduler.cancellations), ["com.example.a.refresh", "com.example.a.processing"])
        XCTAssertThrowsError(try a.cancel(identifier: "com.example.b.refresh"))
        XCTAssertFalse(scheduler.cancellations.contains("com.example.b.refresh"))
    }

    func testIdentifierCanBeRegisteredOnlyOnceAcrossOwners() throws {
        let scheduler = BackgroundTaskSchedulerSpy()
        let center = MiniAppBackgroundTaskCenter(scheduler: scheduler)
        let a = center.tasks(for: context("feature-a"))
        let b = center.tasks(for: context("feature-b"))
        try a.register(identifier: "com.example.shared", kind: .appRefresh) { _ in }

        XCTAssertThrowsError(try b.register(identifier: "com.example.shared", kind: .appRefresh) { _ in }) {
            XCTAssertEqual($0 as? MiniAppBackgroundTaskCenter.Failure, .identifierAlreadyRegistered)
        }
        XCTAssertEqual(scheduler.registrationAttempts, ["com.example.shared"])
    }

    func testExpirationAndCompletionReachNativeTaskAtMostOnce() throws {
        let scheduler = BackgroundTaskSchedulerSpy()
        let center = MiniAppBackgroundTaskCenter(scheduler: scheduler)
        let tasks = center.tasks(for: context("feature-a"))
        var expirationCount = 0
        var launched: MiniAppBackgroundTaskExecution?
        try tasks.register(identifier: "com.example.a.processing", kind: .processing) { task in
            launched = task
            task.onExpiration = { expirationCount += 1 }
        }

        let native = scheduler.launch("com.example.a.processing")
        native.expire()
        native.expire()
        XCTAssertEqual(expirationCount, 1)
        XCTAssertTrue(launched?.isExpired == true)
        XCTAssertTrue(launched?.complete(success: false) == true)
        XCTAssertTrue(launched?.complete(success: true) == false)
        native.expire()

        XCTAssertEqual(expirationCount, 1)
        XCTAssertEqual(native.completions, [false])
    }

    func testNativeTaskRetainsExecutionUntilExpirationCompletesThenReleasesCycle() throws {
        let scheduler = BackgroundTaskSchedulerSpy()
        let center = MiniAppBackgroundTaskCenter(scheduler: scheduler)
        let tasks = center.tasks(for: context("feature-a"))
        weak var execution: MiniAppBackgroundTaskExecution?
        try tasks.register(identifier: "com.example.a.refresh", kind: .appRefresh) { task in
            execution = task
            task.onExpiration = { task.complete(success: false) }
        }

        let native = scheduler.launch("com.example.a.refresh")
        XCTAssertNotNil(execution, "Native expiration ownership must retain execution after launch returns")
        native.expire()

        XCTAssertNil(execution, "Completion must clear native and Feature closure retention")
        XCTAssertEqual(native.completions, [false])
    }

    func testRejectedNativeRegistrationDoesNotClaimIdentifier() throws {
        let scheduler = BackgroundTaskSchedulerSpy(rejectNextRegistration: true)
        let center = MiniAppBackgroundTaskCenter(scheduler: scheduler)
        let tasks = center.tasks(for: context("feature-a"))

        XCTAssertThrowsError(try tasks.register(identifier: "com.example.a.refresh", kind: .appRefresh) { _ in }) {
            XCTAssertEqual($0 as? MiniAppBackgroundTaskCenter.Failure, .nativeRegistrationRejected)
        }
        try tasks.register(identifier: "com.example.a.refresh", kind: .appRefresh) { _ in }
        XCTAssertEqual(scheduler.registrationAttempts, ["com.example.a.refresh", "com.example.a.refresh"])
    }

    private func context(_ id: String) -> MiniAppContext { MiniAppContext(id: MiniAppID(id)) }
}

@MainActor
private final class BackgroundTaskSchedulerSpy: MiniAppBackgroundTaskScheduling {
    struct Submission: Equatable {
        let request: MiniAppBackgroundTaskRequest
        let kind: MiniAppBackgroundTaskKind
    }

    var registrationAttempts: [String] = []
    var registrations: [String: @MainActor (any MiniAppBackgroundTaskNative) -> Void] = [:]
    var submissions: [Submission] = []
    var cancellations: [String] = []
    var rejectNextRegistration: Bool

    init(rejectNextRegistration: Bool = false) {
        self.rejectNextRegistration = rejectNextRegistration
    }

    func register(
        identifier: String,
        kind: MiniAppBackgroundTaskKind,
        launch: @escaping @MainActor (any MiniAppBackgroundTaskNative) -> Void
    ) -> Bool {
        registrationAttempts.append(identifier)
        if rejectNextRegistration { rejectNextRegistration = false; return false }
        registrations[identifier] = launch
        return true
    }

    func submit(_ request: MiniAppBackgroundTaskRequest, kind: MiniAppBackgroundTaskKind) throws {
        submissions.append(.init(request: request, kind: kind))
    }

    func cancel(identifier: String) { cancellations.append(identifier) }

    @discardableResult
    func launch(_ identifier: String) -> BackgroundTaskNativeSpy {
        let task = BackgroundTaskNativeSpy()
        registrations[identifier]?(task)
        return task
    }
}

@MainActor
private final class BackgroundTaskNativeSpy: MiniAppBackgroundTaskNative {
    var expirationHandler: (() -> Void)?
    var completions: [Bool] = []

    func setTaskCompleted(success: Bool) { completions.append(success) }
    func expire() { expirationHandler?() }
}
