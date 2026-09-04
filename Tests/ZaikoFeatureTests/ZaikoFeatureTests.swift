import Foundation
import JibunKitCore
import XCTest
@testable import ZaikoFeature

final class ZaikoFeatureTests: XCTestCase {
    func testZaikoIdentifiersAreNamespaced() {
        let context = MiniAppContext(id: .zaiko)

        XCTAssertEqual(context.storageKey("state"), "zaiko.state")
        XCTAssertEqual(
            context.notificationRequestIdentifier,
            "jibunkit.zaiko.notification"
        )
        XCTAssertEqual(
            context.notificationUserInfo[MiniAppNotificationRoute.miniAppIDUserInfoKey],
            "zaiko"
        )
    }

    func testZaikoIdentifiersDoNotCollideWithExistingFeatures() {
        let issues = MiniAppValidator.validate(ids: [
            MiniAppID("counter"),
            MiniAppID("reminder"),
            MiniAppID("zaiko"),
        ])

        XCTAssertTrue(issues.isEmpty)
    }

    func testRemainingDaysDecreasesWithElapsedTime() {
        let item = InventoryItem(
            id: 1,
            name: "水",
            category: "飲料",
            unit: "本",
            lastPurchased: Date(timeIntervalSince1970: 0),
            currentStock: 10,
            consumptionRatePerDay: 1,
            count: 1,
            needsConsumptionSetup: false
        )
        let pause = GlobalPauseState(active: false, startedAt: nil)
        let now = Date(timeIntervalSince1970: 3 * 86_400)

        let remaining = InventoryDomain.remainingDays(for: item, pauseState: pause, now: now)

        XCTAssertEqual(remaining ?? -1, 7, accuracy: 0.001)
    }

    func testAlertItemsSortBeforeOthers() {
        let pause = GlobalPauseState(active: false, startedAt: nil)
        let now = Date(timeIntervalSince1970: 9 * 86_400)
        let alertItem = InventoryItem(
            id: 1,
            name: "牛乳",
            category: "食品",
            unit: "本",
            lastPurchased: Date(timeIntervalSince1970: 0),
            currentStock: 10,
            consumptionRatePerDay: 1,
            count: 1,
            needsConsumptionSetup: false
        )
        let normalItem = InventoryItem(
            id: 2,
            name: "米",
            category: "食品",
            unit: "kg",
            lastPurchased: Date(timeIntervalSince1970: 0),
            currentStock: 100,
            consumptionRatePerDay: 1,
            count: 1,
            needsConsumptionSetup: false
        )

        let sorted = InventoryDomain.sortedItems(
            [normalItem, alertItem],
            pauseState: pause,
            thresholdDays: 7,
            now: now
        )

        XCTAssertEqual(sorted.map(\.id), [1, 2])
    }

    func testItemDraftValidationRejectsEmptyName() {
        var draft = ItemDraft.empty()
        draft.stock = "1"
        draft.speed = "1"

        XCTAssertThrowsError(try draft.validate())
    }

    func testLegacyNormalizationKeepsNameAndStock() {
        let legacy = LegacyInventoryItem(
            id: nil,
            name: "醤油",
            category: nil,
            unit: nil,
            lastPurchased: nil,
            currentStock: 2,
            lastStock: nil,
            consumptionRatePerDay: 0.5,
            consumptionPace: nil,
            cycle: nil,
            count: nil,
            needsConsumptionSetup: nil
        )

        let item = InventoryDomain.normalize(legacy)

        XCTAssertEqual(item?.name, "醤油")
        XCTAssertEqual(item?.currentStock ?? -1, 2, accuracy: 0.001)
    }
}
