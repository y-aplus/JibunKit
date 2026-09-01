import XCTest
@testable import AppbaseCore

final class SharedGroupResolverTests: XCTestCase {
    func testResolverUsesLogicalGroupWithoutSideStoreRewrite() throws {
        let result = try SharedGroupResolver().resolve(infoDictionary: [
            SharedGroupResolver.logicalGroupInfoKey: "group.com.example.AppbaseIOS.shared",
        ])

        XCTAssertEqual(result, "group.com.example.AppbaseIOS.shared")
    }

    func testResolverSelectsTheSingleSideStoreGroupWithTeamSuffix() throws {
        let result = try SharedGroupResolver().resolve(infoDictionary: [
            SharedGroupResolver.logicalGroupInfoKey: "group.com.example.AppbaseIOS.shared",
            SharedGroupResolver.signedGroupsInfoKey: [
                "group.com.example.unrelated.TEAMID",
                "group.com.example.AppbaseIOS.shared.TEAMID",
            ],
        ])

        XCTAssertEqual(result, "group.com.example.AppbaseIOS.shared.TEAMID")
    }

    func testResolverRejectsMissingSideStoreGroupInsteadOfFallingBack() {
        XCTAssertThrowsError(try SharedGroupResolver().resolve(infoDictionary: [
            SharedGroupResolver.logicalGroupInfoKey: "group.com.example.AppbaseIOS.shared",
            SharedGroupResolver.signedGroupsInfoKey: [
                "group.com.example.unrelated.TEAMID",
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
                "group.com.example.AppbaseIOS.shared.A",
                "group.com.example.AppbaseIOS.shared.B",
            ],
        ])) { error in
            XCTAssertEqual(
                error as? SharedGroupResolutionError,
                .multipleMatchingSignedGroups(
                    logicalIdentifier: "group.com.example.AppbaseIOS.shared",
                    matches: [
                        "group.com.example.AppbaseIOS.shared.A",
                        "group.com.example.AppbaseIOS.shared.B",
                    ]
                )
            )
        }
    }
}
