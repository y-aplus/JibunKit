import XCTest
@testable import JibunKitCore

final class SharedGroupResolverTests: XCTestCase {
    func testResolverUsesLogicalGroupWithoutSideStoreRewrite() throws {
        let result = try SharedGroupResolver().resolve(infoDictionary: [
            SharedGroupResolver.logicalGroupInfoKey: "group.com.jibunkit.shared",
        ])

        XCTAssertEqual(result, "group.com.jibunkit.shared")
    }

    func testResolverSelectsTheSingleSideStoreGroupWithTeamSuffix() throws {
        let result = try SharedGroupResolver().resolve(infoDictionary: [
            SharedGroupResolver.logicalGroupInfoKey: "group.com.jibunkit.shared",
            SharedGroupResolver.signedGroupsInfoKey: [
                "group.com.example.unrelated.TEAMID",
                "group.com.jibunkit.shared.TEAMID",
            ],
        ])

        XCTAssertEqual(result, "group.com.jibunkit.shared.TEAMID")
    }

    func testResolverRejectsMissingSideStoreGroupInsteadOfFallingBack() {
        XCTAssertThrowsError(try SharedGroupResolver().resolve(infoDictionary: [
            SharedGroupResolver.logicalGroupInfoKey: "group.com.jibunkit.shared",
            SharedGroupResolver.signedGroupsInfoKey: [
                "group.com.example.unrelated.TEAMID",
            ],
        ])) { error in
            XCTAssertEqual(
                error as? SharedGroupResolutionError,
                .noMatchingSignedGroup(
                    logicalIdentifier: "group.com.jibunkit.shared"
                )
            )
        }
    }

    func testResolverRejectsAmbiguousSideStoreGroups() {
        XCTAssertThrowsError(try SharedGroupResolver().resolve(infoDictionary: [
            SharedGroupResolver.logicalGroupInfoKey: "group.com.jibunkit.shared",
            SharedGroupResolver.signedGroupsInfoKey: [
                "group.com.jibunkit.shared.A",
                "group.com.jibunkit.shared.B",
            ],
        ])) { error in
            XCTAssertEqual(
                error as? SharedGroupResolutionError,
                .multipleMatchingSignedGroups(
                    logicalIdentifier: "group.com.jibunkit.shared",
                    matches: [
                        "group.com.jibunkit.shared.A",
                        "group.com.jibunkit.shared.B",
                    ]
                )
            )
        }
    }
}
