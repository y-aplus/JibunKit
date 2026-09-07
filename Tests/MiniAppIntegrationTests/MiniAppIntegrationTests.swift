import Foundation
import JibunKitCore
import XCTest
@testable import CounterFeature
@testable import ReminderFeature

final class MiniAppIntegrationTests: XCTestCase {
    func testFeatureIdentifiersAndNamespacesDoNotCollide() {
        let miniApps: [MiniAppID] = [.counter, .reminder]

        XCTAssertEqual(Set(miniApps.map(\.rawValue)).count, miniApps.count)
        XCTAssertEqual(Set(miniApps.map(\.storageNamespace)).count, miniApps.count)
        XCTAssertEqual(
            Set(miniApps.map(\.notificationRequestIdentifier)).count,
            miniApps.count
        )
    }

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

    func testContextDerivedStoresShareDefaultStorageKeys() async throws {
        let suiteName = "MiniAppIntegrationTests.\(UUID().uuidString)"
        try XCTUnwrap(UserDefaults(suiteName: suiteName))
            .removePersistentDomain(forName: suiteName)
        defer {
            UserDefaults(suiteName: suiteName)?
                .removePersistentDomain(forName: suiteName)
        }

        let counterViaContext = CounterStore(
            context: MiniAppContext(id: .counter),
            suiteName: suiteName
        )
        let counterDefault = CounterStore(suiteName: suiteName)
        _ = try await counterViaContext.add(7)
        let counterValue = try await counterDefault.currentValue()
        XCTAssertEqual(counterValue, 7)

        let reminderViaContext = ReminderStore(
            context: MiniAppContext(id: .reminder),
            suiteName: suiteName
        )
        let reminderDefault = ReminderStore(suiteName: suiteName)
        _ = try await reminderViaContext.saveMessage("コンテキスト経由")
        let reminderMessage = try await reminderDefault.currentMessage()
        XCTAssertEqual(reminderMessage, "コンテキスト経由")
    }
}
