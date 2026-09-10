import Foundation
import XCTest
import JibunKitCore

final class MiniAppPasswordCredentialStoreTests: XCTestCase {
    @MainActor
    func testSavingOrdinaryCredentialsDoesNotChangeNativeDefaultSelection() throws {
        let context = MiniAppContext(id: MiniAppID("password-default"))
        let profile = UUID().uuidString
        let store = try MiniAppPasswordCredentialStore(context: context, profile: profile)
        defer { try? store.clear() }
        let space = URLProtectionSpace(host: "one.example", port: 443, protocol: "https", realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        for user in ["one", "two"] {
            store.storage.set(URLCredential(user: user, password: user, persistence: .forSession), for: space)
        }
        let nativeDefault = store.storage.defaultCredential(for: space)?.user
        try store.save()
        let reopened = try MiniAppPasswordCredentialStore(context: context, profile: profile)
        XCTAssertEqual(reopened.storage.defaultCredential(for: space)?.user, nativeDefault)
        XCTAssertEqual(reopened.storage.credentials(for: space)?.count, 2)
    }

    @MainActor
    func testProtectionSpacesUsersAndDefaultSelectionSurviveReconstruction() throws {
        let context = MiniAppContext(id: MiniAppID("password-routing"))
        let profile = UUID().uuidString
        let store = try MiniAppPasswordCredentialStore(context: context, profile: profile)
        defer { try? store.clear() }
        let spaces = [
            URLProtectionSpace(host: "one.example", port: 443, protocol: "https", realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
            URLProtectionSpace(host: "two.example", port: 443, protocol: "https", realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
            URLProtectionSpace(host: "one.example", port: 8443, protocol: "https", realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
            URLProtectionSpace(host: "one.example", port: 443, protocol: "https", realm: "other", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
            URLProtectionSpace(host: "one.example", port: 443, protocol: "http", realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
            URLProtectionSpace(host: "one.example", port: 443, protocol: "https", realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPDigest),
            URLProtectionSpace(proxyHost: "one.example", port: 443, type: NSURLProtectionSpaceHTTPSProxy, realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
            URLProtectionSpace(host: "one.example", port: 443, protocol: "https", realm: nil, authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        ]
        for (index, space) in spaces.enumerated() {
            store.storage.set(URLCredential(user: "first", password: "first-\(index)", persistence: .forSession), for: space)
            store.storage.setDefaultCredential(URLCredential(user: "selected", password: "selected-\(index)", persistence: .forSession), for: space)
        }
        try store.save()
        let reopened = try MiniAppPasswordCredentialStore(context: context, profile: profile)
        XCTAssertEqual(reopened.storage.allCredentials.count, spaces.count)
        XCTAssertFalse(reopened.storage === store.storage)
        XCTAssertFalse(reopened.storage === URLCredentialStorage.shared)
        for (index, space) in spaces.enumerated() {
            XCTAssertEqual(reopened.storage.credentials(for: space)?.count, 2)
            XCTAssertEqual(reopened.storage.credentials(for: space)?["first"]?.password, "first-\(index)")
            XCTAssertEqual(reopened.storage.defaultCredential(for: space)?.password, "selected-\(index)")
            XCTAssertEqual(reopened.storage.defaultCredential(for: space)?.persistence, .forSession)
        }
        let first = try XCTUnwrap(reopened.storage.credentials(for: spaces[0])?["first"])
        reopened.storage.setDefaultCredential(first, for: spaces[0])
        try reopened.save()
        try reopened.reload()
        XCTAssertEqual(reopened.storage.defaultCredential(for: spaces[0])?.user, "first")
    }

    @MainActor
    func testOwnerAndProfileLogoutPreserveOtherPasswordsAndCookies() throws {
        let a = MiniAppContext(id: MiniAppID("password-a"))
        let b = MiniAppContext(id: MiniAppID("password-b"))
        let profile = UUID().uuidString
        let owners = [(a, profile), (a, profile + "/../別"), (b, profile)]
        let stores = try owners.map { try MiniAppPasswordCredentialStore(context: $0.0, profile: $0.1) }
        let cookies = try MiniAppCookieStore(context: a, profile: profile)
        defer { stores.forEach { try? $0.clear() }; try? cookies.clear() }
        cookies.storage.setCookie(try XCTUnwrap(HTTPCookie(properties: [
            .domain: "one.example", .path: "/", .name: "account", .value: "cookie",
            .expires: Date.now.addingTimeInterval(3600)
        ])))
        try cookies.save()
        let space = URLProtectionSpace(host: "one.example", port: 443, protocol: "https", realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        for (index, store) in stores.enumerated() {
            store.storage.setDefaultCredential(URLCredential(user: "same", password: "owner-\(index)", persistence: .forSession), for: space)
            try store.save()
        }
        try stores[0].clear()
        XCTAssertNil(stores[0].storage.defaultCredential(for: space))
        for (index, owner) in owners.enumerated() {
            let reopened = try MiniAppPasswordCredentialStore(context: owner.0, profile: owner.1)
            XCTAssertEqual(reopened.storage.defaultCredential(for: space)?.password, index == 0 ? nil : "owner-\(index)")
        }
        let preservedCookies = try MiniAppCookieStore(context: a, profile: profile)
        XCTAssertEqual(preservedCookies.storage.cookies?.first?.value, "cookie")
    }

    @MainActor
    func testInvalidArchiveDoesNotPartiallyReplaceLiveCredentials() throws {
        let context = MiniAppContext(id: MiniAppID("password-invalid"))
        let profile = UUID().uuidString
        let store = try MiniAppPasswordCredentialStore(context: context, profile: profile)
        let keychain = MiniAppKeychain(context: context, service: "network-passwords-v1")
        defer { try? store.clear() }
        let space = URLProtectionSpace(host: "one.example", port: 443, protocol: "https", realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        store.storage.setDefaultCredential(URLCredential(user: "same", password: "live", persistence: .forSession), for: space)
        try store.save()
        let good = try XCTUnwrap(try keychain.data(for: profile))
        let archive = try XCTUnwrap(PropertyListSerialization.propertyList(from: good, format: nil) as? [String: Any])
        var entry = try XCTUnwrap((archive["spaces"] as? [[String: Any]])?.first)
        entry["passwords"] = [["user": "same", "password": "replacement"]]
        var missingDefault = entry
        missingDefault["defaultUser"] = "absent"
        var duplicateUser = entry
        duplicateUser["passwords"] = [["user": "same", "password": "one"], ["user": "same", "password": "two"]]
        let invalid: [[String: Any]] = [
            ["version": 2, "spaces": [entry]],
            ["version": 1, "spaces": [entry, ["invalid": true]]],
            ["version": 1, "spaces": [entry, entry]],
            ["version": 1, "spaces": [missingDefault]],
            ["version": 1, "spaces": [duplicateUser]]
        ]
        for item in invalid {
            let data = try PropertyListSerialization.data(fromPropertyList: item, format: .binary, options: 0)
            try keychain.set(data, for: profile)
            XCTAssertThrowsError(try store.reload())
            XCTAssertEqual(store.storage.defaultCredential(for: space)?.password, "live")
            XCTAssertEqual(try keychain.data(for: profile), data)
        }
        try keychain.set(good, for: profile)
        try store.reload()
        XCTAssertEqual(store.storage.defaultCredential(for: space)?.password, "live")
    }
}
