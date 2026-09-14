import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import XCTest

/// No JibunKit import, notification cleanup, or Feature lifecycle. Run in a
/// fresh app on a freshly booted simulator to isolate the first native request.
@MainActor
final class SpotlightColdStartTests: XCTestCase {
    func testColdDeletionThenAsyncOverlayAndIndexing() async {
        let index = CSSearchableIndex.default()
        let domain = "cold-start." + UUID().uuidString
        print("SPOTLIGHT_BASELINE indexingAvailable=\(CSSearchableIndex.isIndexingAvailable())")

        // Continue after a failed bounded operation: whether the next request
        // recovers is evidence, not an automatic retry that turns failure green.
        await measure("cold-native-empty-delete") { completion in
            index.deleteSearchableItems(withDomainIdentifiers: [domain], completionHandler: completion)
        }
        await measure("second-native-empty-delete") { completion in
            index.deleteSearchableItems(withDomainIdentifiers: [domain], completionHandler: completion)
        }
        await measure("async-overlay-empty-delete") { completion in
            Task {
                do {
                    try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
                    completion(nil)
                } catch { completion(error) }
            }
        }

        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = "Cold-start native index item"
        let item = CSSearchableItem(uniqueIdentifier: domain + ".item",
                                    domainIdentifier: domain, attributeSet: attributes)
        await measure("native-index") { completion in
            index.indexSearchableItems([item], completionHandler: completion)
        }
        await measure("native-populated-delete") { completion in
            index.deleteSearchableItems(withDomainIdentifiers: [domain], completionHandler: completion)
        }
    }

    private func measure(
        _ label: String,
        start: (@escaping @Sendable (Error?) -> Void) -> Void
    ) async {
        let done = XCTestExpectation(description: label)
        let started = Date()
        print("SPOTLIGHT_BASELINE start=\(label)")
        start { error in
            print("SPOTLIGHT_BASELINE callback=\(label) seconds=\(Date().timeIntervalSince(started)) error=\(String(describing: error))")
            XCTAssertNil(error, label)
            done.fulfill()
        }
        let result = await XCTWaiter.fulfillment(of: [done], timeout: 30)
        print("SPOTLIGHT_BASELINE wait=\(label) result=\(result.rawValue)")
        XCTAssertEqual(result, .completed, "\(label): native completion absent after 30 seconds")
    }
}
