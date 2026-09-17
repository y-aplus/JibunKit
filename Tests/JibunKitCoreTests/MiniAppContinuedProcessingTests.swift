import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppContinuedProcessingTests: XCTestCase {
    func testTwoOwnersReceiveOnlyTheirLaunchAndProgress() throws {
        let scheduler = ContinuedSchedulerSpy()
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let a = center.tasks(for: context("continued-a"))
        let b = center.tasks(for: context("continued-b"))
        var launches: [String] = []

        try a.register(identifier: "com.example.export-a") { execution in
            launches.append("a")
            execution.reportProgress(completed: 2, total: 5)
            execution.updateTitle("Export A", subtitle: "2 of 5")
        }
        try b.register(identifier: "com.example.export-b") { execution in
            launches.append("b")
            execution.reportProgress(completed: 1, total: 3)
        }

        let nativeB = scheduler.launch("com.example.export-b")
        let nativeA = scheduler.launch("com.example.export-a")
        XCTAssertEqual(launches, ["b", "a"])
        XCTAssertEqual(nativeB.progress, [.init(completed: 1, total: 3)])
        XCTAssertEqual(nativeA.progress, [.init(completed: 2, total: 5)])
        XCTAssertEqual(nativeA.titles, [.init(title: "Export A", subtitle: "2 of 5")])
    }

    func testSubmissionPreservesPresentationStrategyAndOwner() throws {
        let scheduler = ContinuedSchedulerSpy()
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let a = center.tasks(for: context("continued-a"))
        let b = center.tasks(for: context("continued-b"))
        try a.register(identifier: "com.example.export") { _ in }
        let request = MiniAppContinuedProcessingRequest(
            identifier: "com.example.export",
            title: "Export",
            subtitle: "Preparing",
            strategy: .fail
        )

        try a.submit(request)
        XCTAssertEqual(scheduler.submissions, [request])
        XCTAssertThrowsError(try b.submit(request)) {
            XCTAssertEqual($0 as? MiniAppContinuedProcessingCenter.Failure, .identifierNotOwned)
        }
        XCTAssertThrowsError(try a.submit(.init(
            identifier: request.identifier, title: "", subtitle: "Preparing"
        ))) {
            XCTAssertEqual($0 as? MiniAppContinuedProcessingCenter.Failure, .invalidPresentation)
        }
    }

    func testExpirationCleanupAndCompletionAreDeliveredOnce() throws {
        let scheduler = ContinuedSchedulerSpy()
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let tasks = center.tasks(for: context("continued-a"))
        var expirationCount = 0
        var launched: MiniAppContinuedProcessingExecution?
        try tasks.register(identifier: "com.example.export") { execution in
            launched = execution
            execution.onExpiration = { expirationCount += 1 }
        }

        let native = scheduler.launch("com.example.export")
        native.expire()
        native.expire()
        XCTAssertTrue(launched?.isExpired == true)
        XCTAssertEqual(expirationCount, 1)
        XCTAssertTrue(launched?.complete(success: false) == true)
        XCTAssertTrue(launched?.complete(success: true) == false)
        XCTAssertEqual(native.completions, [false])
    }

    func testLateExpirationHandlerIsDeliveredAndCenterRetainsUntilCompletion() throws {
        let scheduler = ContinuedSchedulerSpy()
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let tasks = center.tasks(for: context("continued-a"))
        weak var launched: MiniAppContinuedProcessingExecution?
        try tasks.register(identifier: "com.example.export") { launched = $0 }

        let native = scheduler.launch("com.example.export")
        native.expire()
        var expirationCount = 0
        launched?.onExpiration = { expirationCount += 1 }
        XCTAssertEqual(expirationCount, 1)
        XCTAssertNotNil(launched)
        launched?.complete(success: false)
        XCTAssertNil(launched)
    }

    func testCancellationAndRegistrationFailureRemainOwnerScoped() throws {
        let scheduler = ContinuedSchedulerSpy(rejectNextRegistration: true)
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let a = center.tasks(for: context("continued-a"))
        let b = center.tasks(for: context("continued-b"))

        XCTAssertThrowsError(try a.register(identifier: "com.example.export-a") { _ in }) {
            XCTAssertEqual($0 as? MiniAppContinuedProcessingCenter.Failure, .nativeRegistrationRejected)
        }
        try a.register(identifier: "com.example.export-a") { _ in }
        try b.register(identifier: "com.example.export-b") { _ in }
        try a.cancelPendingRequest(identifier: "com.example.export-a")
        XCTAssertEqual(scheduler.cancellations, ["com.example.export-a"])
        XCTAssertThrowsError(try a.cancelPendingRequest(identifier: "com.example.export-b"))
        XCTAssertEqual(scheduler.cancellations, ["com.example.export-a"])
    }

    private func context(_ id: String) -> MiniAppContext { MiniAppContext(id: MiniAppID(id)) }
}

@MainActor
private final class ContinuedSchedulerSpy: MiniAppContinuedProcessingScheduling {
    var registrations: [String: @MainActor (any MiniAppContinuedProcessingNative) -> Void] = [:]
    var submissions: [MiniAppContinuedProcessingRequest] = []
    var cancellations: [String] = []
    var rejectNextRegistration: Bool

    init(rejectNextRegistration: Bool = false) {
        self.rejectNextRegistration = rejectNextRegistration
    }

    func register(
        identifier: String,
        launch: @escaping @MainActor (any MiniAppContinuedProcessingNative) -> Void
    ) -> Bool {
        if rejectNextRegistration { rejectNextRegistration = false; return false }
        registrations[identifier] = launch
        return true
    }

    func submit(_ request: MiniAppContinuedProcessingRequest) throws { submissions.append(request) }
    func cancel(identifier: String) { cancellations.append(identifier) }

    func launch(_ identifier: String) -> ContinuedNativeSpy {
        let native = ContinuedNativeSpy()
        registrations[identifier]?(native)
        return native
    }
}

@MainActor
private final class ContinuedNativeSpy: MiniAppContinuedProcessingNative {
    struct ProgressUpdate: Equatable { let completed: Int64; let total: Int64 }
    struct TitleUpdate: Equatable { let title: String; let subtitle: String }

    var expirationHandler: (@MainActor @Sendable () -> Void)?
    var progress: [ProgressUpdate] = []
    var titles: [TitleUpdate] = []
    var completions: [Bool] = []

    func updateProgress(completed: Int64, total: Int64) {
        progress.append(.init(completed: completed, total: total))
    }
    func updateTitle(_ title: String, subtitle: String) {
        titles.append(.init(title: title, subtitle: subtitle))
    }
    func setTaskCompleted(success: Bool) { completions.append(success) }
    func expire() {
        let expirationHandler = expirationHandler
        self.expirationHandler = nil
        expirationHandler?()
    }
}
