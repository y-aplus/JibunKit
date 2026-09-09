import XCTest
@testable import JibunKitCore

final class MiniAppNotificationActionTests: XCTestCase {
    @MainActor
    func testCustomAndDismissReachOnlyOwnerWithoutNavigation() async {
        let owner = MiniAppID("first")
        var received: [MiniAppNotificationAction] = []
        var opens = 0
        let handler: @MainActor (MiniAppNotificationAction) async -> Void = { received.append($0) }
        let kinds: [MiniAppNotificationAction.Kind] = [.custom("reply"), .dismiss]
        for kind in kinds {
            let action = MiniAppNotificationAction(kind: kind, requestIdentifier: "request",
                destination: "record", userText: "返答")
            await MiniAppNotificationActionDelivery.deliver(action,
                route: MiniAppRoute(id: owner, destination: "record"),
                handlerForOwner: { $0 == owner ? handler : nil }, open: { _ in opens += 1 })
            await MiniAppNotificationActionDelivery.deliver(action,
                route: MiniAppRoute(id: MiniAppID("other"), destination: nil),
                handlerForOwner: { $0 == owner ? handler : nil }, open: { _ in opens += 1 })
        }
        XCTAssertEqual(opens, 0)
        XCTAssertEqual(received.map(\.kind), [.custom("reply"), .dismiss])
        XCTAssertEqual(received.first?.userText, "返答")
        XCTAssertEqual(received.first?.destination, "record")
    }

    @MainActor
    func testDefaultOpenPreservesRouteWithoutAnActionHandler() async {
        let route = MiniAppRoute(id: MiniAppID("counter"), destination: nil)
        var opened: MiniAppRoute?
        let action = MiniAppNotificationAction(kind: .open, requestIdentifier: "legacy", destination: nil, userText: nil)
        await MiniAppNotificationActionDelivery.deliver(action, route: route,
            handlerForOwner: { _ in nil }, open: { opened = $0 })
        XCTAssertEqual(opened, route)
    }
}
