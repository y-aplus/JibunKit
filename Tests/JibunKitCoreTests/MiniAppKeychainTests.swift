#if canImport(Security)
import Foundation
import XCTest
import JibunKitCore

final class MiniAppKeychainTests: XCTestCase {
    func testNativeStorageUpdateAndLogoutPreserveOtherFeatureAndService() throws {
        let service = "test-" + UUID().uuidString
        let a = MiniAppContext(id: MiniAppID("keychain-a"))
        let first = MiniAppKeychain(context: a, service: service)
        let second = MiniAppKeychain(context: MiniAppContext(id: MiniAppID("keychain-b")), service: service)
        let otherService = MiniAppKeychain(context: a, service: service + "-other")
        defer {
            try? first.removeAll()
            try? second.removeAll()
            try? otherService.removeAll()
        }
        try first.set(Data("a".utf8), for: "same-account")
        try second.set(Data("b".utf8), for: "same-account")
        try otherService.set(Data("other".utf8), for: "same-account")
        try first.set(Data("updated".utf8), for: "same-account")
        XCTAssertEqual(try first.data(for: "same-account"), Data("updated".utf8))
        try first.set(Data(), for: "another-account")
        try first.remove(account: "same-account")
        XCTAssertNil(try first.data(for: "same-account"))
        XCTAssertEqual(try first.data(for: "another-account"), Data())
        try first.removeAll()
        XCTAssertNil(try first.data(for: "another-account"))
        XCTAssertEqual(try second.data(for: "same-account"), Data("b".utf8))
        XCTAssertEqual(try otherService.data(for: "same-account"), Data("other".utf8))
        XCTAssertEqual(try MiniAppKeychain(context: a, service: service + "-other").data(for: "same-account"), Data("other".utf8))
    }
}
#endif
