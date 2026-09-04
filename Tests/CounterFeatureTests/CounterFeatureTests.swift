import Foundation
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

}
