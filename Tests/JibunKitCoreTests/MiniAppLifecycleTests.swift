import XCTest
import JibunKitCore

final class MiniAppLifecycleTests: XCTestCase {
    @MainActor
    func testAllIntegrationsReceiveInitialPhaseAndResumeWithoutDuplicateEvents() {
        var first: [MiniAppHostPhase] = []
        var second: [MiniAppHostPhase] = []
        let dispatcher = MiniAppLifecycleDispatcher(handlers: [
            { first.append($0) }, { second.append($0) },
        ])
        let phases: [MiniAppHostPhase] = [.inactive, .active, .active, .inactive, .background, .background, .active]
        for phase in phases {
            dispatcher.update(phase)
        }
        let expected: [MiniAppHostPhase] = [.inactive, .active, .inactive, .background, .active]
        XCTAssertEqual(first, expected)
        XCTAssertEqual(second, expected)
    }
}
