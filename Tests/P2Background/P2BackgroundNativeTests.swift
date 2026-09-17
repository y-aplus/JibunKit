#if os(iOS)
import BackgroundTasks
import JibunKitCore
import XCTest
@testable import JibunKit_App

@MainActor
final class P2BackgroundNativeTests: XCTestCase {
    func testDefinitionsExposeTwoIndependentHostLaunchRegistrations() throws {
        let definitions = P2BackgroundProbe.definitions
        XCTAssertEqual(definitions.map(\.id), [MiniAppID("p2-background-a"), MiniAppID("p2-background-b")])
        XCTAssertTrue(definitions.allSatisfy { $0.onHostLaunch != nil })
        XCTAssertNotEqual(P2BackgroundProbe.ownerA.taskIdentifier, P2BackgroundProbe.ownerB.taskIdentifier)
        XCTAssertTrue(P2BackgroundProbe.ownerA.taskIdentifier.hasPrefix("com.jibunkit.app."))
        XCTAssertTrue(P2BackgroundProbe.ownerB.taskIdentifier.hasPrefix("com.jibunkit.app."))
    }

    func testCurrentSDKConstructsContinuedRequestsWithPresentationAndStrategies() {
        let queued = BGContinuedProcessingTaskRequest(
            identifier: P2BackgroundProbe.ownerA.taskIdentifier,
            title: "Export A",
            subtitle: "Waiting"
        )
        queued.strategy = .queue
        let immediate = BGContinuedProcessingTaskRequest(
            identifier: P2BackgroundProbe.ownerB.taskIdentifier,
            title: "Export B",
            subtitle: "Waiting"
        )
        immediate.strategy = .fail

        XCTAssertEqual(queued.identifier, P2BackgroundProbe.ownerA.taskIdentifier)
        XCTAssertEqual(queued.title, "Export A")
        XCTAssertEqual(queued.subtitle, "Waiting")
        XCTAssertEqual(queued.strategy, .queue)
        XCTAssertEqual(immediate.strategy, .fail)
    }
}
#endif
