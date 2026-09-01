import Foundation
import XCTest
@testable import CounterFeature
@testable import ReminderFeature

final class MiniAppIntegrationTests: XCTestCase {
    func testCounterAndReminderPersistWithoutChangingEachOther() async throws {
        let suiteName = "MiniAppIntegrationTests.\(UUID().uuidString)"
        try XCTUnwrap(UserDefaults(suiteName: suiteName))
            .removePersistentDomain(forName: suiteName)
        defer {
            UserDefaults(suiteName: suiteName)?
                .removePersistentDomain(forName: suiteName)
        }

        let counter = CounterStore(suiteName: suiteName)
        let reminder = ReminderStore(suiteName: suiteName)

        let counterValue = try await counter.add(4)
        try await reminder.saveMessage("水を飲む")

        let reloadedCounter = CounterStore(suiteName: suiteName)
        let reloadedReminder = ReminderStore(suiteName: suiteName)
        let reloadedCounterValue = try await reloadedCounter.currentValue()
        let reloadedReminderMessage = try await reloadedReminder.currentMessage()

        XCTAssertEqual(counterValue, 4)
        XCTAssertEqual(reloadedCounterValue, 4)
        XCTAssertEqual(reloadedReminderMessage, "水を飲む")

        try await reminder.saveMessage("出発する")
        let finalCounterValue = try await counter.currentValue()
        let finalReminderMessage = try await reminder.currentMessage()

        XCTAssertEqual(finalCounterValue, 4)
        XCTAssertEqual(finalReminderMessage, "出発する")
    }
}
