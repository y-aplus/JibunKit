import XCTest
@testable import JibunKitCore

final class MiniAppRemovalProviderTests: XCTestCase, @unchecked Sendable {
    func testMetadataDoesNotInvokeRemovalAndCallbackRunsOnlyWhenCalled() async throws {
        let probe = RemovalProbe()
        let provider = MiniAppRemovalProvider(
            id: MiniAppID("feature-a"),
            dataDescription: "Saved local entries and attachments",
            removeData: { await probe.remove() })

        XCTAssertEqual(provider.id, MiniAppID("feature-a"))
        XCTAssertEqual(provider.dataDescription, "Saved local entries and attachments")
        let before = await probe.count
        XCTAssertEqual(before, 0)
        try await provider.removeData()
        let after = await probe.count
        XCTAssertEqual(after, 1)
    }
}

private actor RemovalProbe {
    private(set) var count = 0
    func remove() { count += 1 }
}
