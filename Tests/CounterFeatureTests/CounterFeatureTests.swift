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

    func testResolverUsesLogicalGroupWithoutSideStoreRewrite() throws {
        let result = try SharedGroupResolver().resolve(infoDictionary: [
            SharedGroupResolver.logicalGroupInfoKey: "group.com.example.AppbaseIOS.shared",
        ])

        XCTAssertEqual(result, "group.com.example.AppbaseIOS.shared")
    }

    func testResolverSelectsTheSingleSideStoreGroupBySuffix() throws {
        let result = try SharedGroupResolver().resolve(infoDictionary: [
            SharedGroupResolver.logicalGroupInfoKey: "group.com.example.AppbaseIOS.shared",
            SharedGroupResolver.signedGroupsInfoKey: [
                "TEAMID.group.com.example.unrelated",
                "TEAMID.group.com.example.AppbaseIOS.shared",
            ],
        ])

        XCTAssertEqual(result, "TEAMID.group.com.example.AppbaseIOS.shared")
    }

    func testResolverRejectsMissingSideStoreGroupInsteadOfFallingBack() {
        XCTAssertThrowsError(try SharedGroupResolver().resolve(infoDictionary: [
            SharedGroupResolver.logicalGroupInfoKey: "group.com.example.AppbaseIOS.shared",
            SharedGroupResolver.signedGroupsInfoKey: [
                "TEAMID.group.com.example.unrelated",
            ],
        ])) { error in
            XCTAssertEqual(
                error as? SharedGroupResolutionError,
                .noMatchingSignedGroup(
                    logicalIdentifier: "group.com.example.AppbaseIOS.shared"
                )
            )
        }
    }

    func testResolverRejectsAmbiguousSideStoreGroups() {
        XCTAssertThrowsError(try SharedGroupResolver().resolve(infoDictionary: [
            SharedGroupResolver.logicalGroupInfoKey: "group.com.example.AppbaseIOS.shared",
            SharedGroupResolver.signedGroupsInfoKey: [
                "A.group.com.example.AppbaseIOS.shared",
                "B.group.com.example.AppbaseIOS.shared",
            ],
        ])) { error in
            XCTAssertEqual(
                error as? SharedGroupResolutionError,
                .multipleMatchingSignedGroups(
                    logicalIdentifier: "group.com.example.AppbaseIOS.shared",
                    matches: [
                        "A.group.com.example.AppbaseIOS.shared",
                        "B.group.com.example.AppbaseIOS.shared",
                    ]
                )
            )
        }
    }
}
