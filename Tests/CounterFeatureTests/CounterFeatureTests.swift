import Foundation
import JibunKitCore
import XCTest
@testable import CounterFeature

final class CounterFeatureTests: XCTestCase {
    func testAddReturnsAndPersistsUpdatedValue() async throws {
        let suiteName = "CounterFeatureTests.\(UUID().uuidString)"
        try XCTUnwrap(UserDefaults(suiteName: suiteName))
            .removePersistentDomain(forName: suiteName)
        defer {
            UserDefaults(suiteName: suiteName)?
                .removePersistentDomain(forName: suiteName)
        }

        let store = CounterStore(suiteName: suiteName)

        let initialValue = try await store.currentValue()
        let valueAfterAddingTwo = try await store.add(2)
        let valueAfterSubtractingOne = try await store.add(-1)
        let reloadedStore = CounterStore(suiteName: suiteName)
        let persistedValue = try await reloadedStore.currentValue()

        XCTAssertEqual(initialValue, 0)
        XCTAssertEqual(valueAfterAddingTwo, 2)
        XCTAssertEqual(valueAfterSubtractingOne, 1)
        XCTAssertEqual(persistedValue, 1)
    }

    func testConcurrentAddsAreAllPersisted() async throws {
        let suiteName = "CounterFeatureTests.\(UUID().uuidString)"
        try XCTUnwrap(UserDefaults(suiteName: suiteName))
            .removePersistentDomain(forName: suiteName)
        defer {
            UserDefaults(suiteName: suiteName)?
                .removePersistentDomain(forName: suiteName)
        }

        let store = CounterStore(suiteName: suiteName)
        let additionCount = 100

        let returnedValues = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<additionCount {
                group.addTask {
                    try await store.add(1)
                }
            }

            var values: [Int] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }

        let reloadedStore = CounterStore(suiteName: suiteName)
        let currentValue = try await store.currentValue()
        let persistedValue = try await reloadedStore.currentValue()

        XCTAssertEqual(Set(returnedValues), Set(1...additionCount))
        XCTAssertEqual(currentValue, additionCount)
        XCTAssertEqual(persistedValue, additionCount)
    }

    func testOverflowReturnsError() {
        XCTAssertThrowsError(try CounterStore.updatedValue(Int.max, adding: 1)) { error in
            XCTAssertEqual(error as? CounterStoreError, .valueOutOfRange)
        }
    }

    func testConcurrentAddsAcrossStoreInstancesAreAllPersisted() async throws {
        let suiteName = "CounterFeatureTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let context = MiniAppContext(id: .counter)
        let stores = (0..<4).map { _ in CounterStore(context: context, suiteName: suiteName) }
        let additionCount = 400
        let values = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<additionCount {
                let store = stores[index % stores.count]
                group.addTask { try await store.add(1) }
            }
            var values: [Int] = []
            for try await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(Set(values), Set(1...additionCount))
        let persisted = try await CounterStore(context: context, suiteName: suiteName).currentValue()
        XCTAssertEqual(persisted, additionCount)
    }

    func testFailedUpdateReleasesSharedAccessAndKeepsSavedValue() async throws {
        let suiteName = "CounterFeatureTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let first = CounterStore(suiteName: suiteName)
        let second = CounterStore(suiteName: suiteName)
        _ = try await first.add(Int.max)
        do {
            _ = try await first.add(1)
            XCTFail("Overflow must fail without changing the saved value")
        } catch {
            XCTAssertEqual(error as? CounterStoreError, .valueOutOfRange)
        }
        let value = try await second.add(-1)
        XCTAssertEqual(value, Int.max - 1)
    }

}
