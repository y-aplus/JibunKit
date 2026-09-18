#if os(iOS)
import Foundation
import XCTest
import JibunKitCore

@MainActor
final class P2ActionNativeTests: XCTestCase {
    func testActionEntrySelectsActionSpecificCopyAndContract() {
        let controller = ActionViewController()
        XCTAssertEqual(controller.incomingPresentation, .action)
        XCTAssertEqual(controller.incomingPresentation.accessibilityPrefix, "action")
        XCTAssertTrue(controller.incomingPresentation.explanation.contains("出力項目は返しません"))
        XCTAssertNotEqual(controller.incomingPresentation, .share)
    }

    func testTwoOwnerAdmissionAndDurableReceiptRemainOwned() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = try MiniAppIncomingStore(containerURL: root)
        try inbox.publish([P2ActionProbe.alpha, P2ActionProbe.beta])

        let alphaReceipt = try inbox.enqueue(for: MiniAppID(P2ActionProbe.alpha.id), inputs: [.text("alpha")])
        let betaReceipt = try inbox.enqueue(for: MiniAppID(P2ActionProbe.beta.id), inputs: [.url(URL(string: "https://example.invalid/beta")!)])
        XCTAssertEqual(alphaReceipt.owner, P2ActionProbe.alpha.id)
        XCTAssertEqual(betaReceipt.owner, P2ActionProbe.beta.id)

        try inbox.setAdmission(P2ActionProbe.alpha, enabled: false)
        XCTAssertThrowsError(try inbox.enqueue(for: MiniAppID(P2ActionProbe.alpha.id), inputs: [.text("closed")])) {
            XCTAssertEqual($0 as? MiniAppIncomingError, .unavailableOwner(P2ActionProbe.alpha.id))
        }
        XCTAssertEqual(try inbox.pending(for: MiniAppID(P2ActionProbe.alpha.id)).receipts.map(\.id), [alphaReceipt.id])
        XCTAssertEqual(try inbox.pending(for: MiniAppID(P2ActionProbe.beta.id)).receipts.map(\.id), [betaReceipt.id])
    }
}
#endif
