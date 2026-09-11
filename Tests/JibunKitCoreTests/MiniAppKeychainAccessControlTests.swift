#if canImport(Security) && canImport(LocalAuthentication)
import Foundation
import LocalAuthentication
import Security
import XCTest
import JibunKitCore

final class MiniAppKeychainAccessControlTests: XCTestCase {
    func testNativeAccessControlPersistsAcrossDataOnlyUpdate() throws {
        let keychain = makeKeychain(feature: "access-control")
        let account = UUID().uuidString
        defer { try? keychain.removeAll() }
        let accessControl = try makeAccessControl(flags: [])

        try setAccessControlled(
            Data("original".utf8),
            for: account,
            in: keychain,
            accessControl: accessControl
        )
        XCTAssertEqual(try accessibility(for: account, in: keychain), kSecAttrAccessibleWhenUnlocked as String)

        try keychain.set(Data("updated".utf8), for: account)
        XCTAssertEqual(try keychain.data(for: account), Data("updated".utf8))
        XCTAssertEqual(try accessibility(for: account, in: keychain), kSecAttrAccessibleWhenUnlocked as String)
    }

    func testRejectsSeparateAccessibilityWithAccessControlWithoutCreatingItem() throws {
        let keychain = makeKeychain(feature: "invalid-protection")
        let account = UUID().uuidString
        defer { try? keychain.removeAll() }
        let accessControl = try makeAccessControl(flags: [])

        XCTAssertThrowsError(try keychain.set(
            Data("secret".utf8),
            for: account,
            accessibility: kSecAttrAccessibleAfterFirstUnlock,
            accessControl: accessControl
        )) { error in
            XCTAssertEqual((error as? MiniAppKeychain.Failure)?.status, errSecParam)
        }
        XCTAssertNil(try keychain.data(for: account))
    }

    func testNonInteractiveAuthenticationFailureKeepsProtectedItemAndOtherOwner() throws {
        let service = "access-control-" + UUID().uuidString
        let protected = MiniAppKeychain(
            context: MiniAppContext(id: MiniAppID("protected-owner")),
            service: service
        )
        let other = MiniAppKeychain(
            context: MiniAppContext(id: MiniAppID("other-owner")),
            service: service
        )
        let account = "same-account"
        let cleanupContext = LAContext()
        cleanupContext.interactionNotAllowed = true
        defer {
            try? protected.removeAll(authenticationContext: cleanupContext)
            try? other.removeAll()
        }
        let accessControl = try makeAccessControl(flags: .userPresence)
        let addContext = LAContext()
        addContext.interactionNotAllowed = true
        try setAccessControlled(
            Data("original".utf8),
            for: account,
            in: protected,
            accessControl: accessControl,
            authenticationContext: addContext
        )
        try other.set(Data("other".utf8), for: account)

        let nonInteractiveContext = LAContext()
        nonInteractiveContext.interactionNotAllowed = true
        XCTAssertThrowsError(try protected.set(
            Data("replacement".utf8),
            for: account,
            authenticationContext: nonInteractiveContext
        )) { error in
            let status = (error as? MiniAppKeychain.Failure)?.status
            XCTAssertTrue(
                status == errSecInteractionNotAllowed || status == errSecAuthFailed,
                "Unexpected non-interactive authentication status: \(String(describing: status))"
            )
        }

        let verificationContext = LAContext()
        verificationContext.interactionNotAllowed = true
        XCTAssertThrowsError(try protected.data(
            for: account,
            authenticationContext: verificationContext
        )) { error in
            let status = (error as? MiniAppKeychain.Failure)?.status
            XCTAssertNotEqual(status, errSecItemNotFound)
            XCTAssertTrue(
                status == errSecInteractionNotAllowed || status == errSecAuthFailed,
                "Unexpected protected read status after rejected update: \(String(describing: status))"
            )
        }
        XCTAssertEqual(try other.data(for: account), Data("other".utf8))
    }

    func testCallerOwnedContextsKeepReadsAndRemovalScoped() throws {
        let service = "contexts-" + UUID().uuidString
        let first = MiniAppKeychain(
            context: MiniAppContext(id: MiniAppID("context-owner-a")),
            service: service
        )
        let second = MiniAppKeychain(
            context: MiniAppContext(id: MiniAppID("context-owner-b")),
            service: service
        )
        defer {
            try? first.removeAll()
            try? second.removeAll()
        }
        let firstContext = LAContext()
        firstContext.interactionNotAllowed = true
        let secondContext = LAContext()
        secondContext.interactionNotAllowed = true

        try first.set(Data("first".utf8), for: "same", authenticationContext: firstContext)
        try second.set(Data("second".utf8), for: "same", authenticationContext: secondContext)
        XCTAssertEqual(try first.data(for: "same", authenticationContext: firstContext), Data("first".utf8))
        XCTAssertEqual(try second.data(for: "same", authenticationContext: secondContext), Data("second".utf8))

        try first.remove(account: "same", authenticationContext: firstContext)
        XCTAssertNil(try first.data(for: "same", authenticationContext: firstContext))
        XCTAssertEqual(try second.data(for: "same", authenticationContext: secondContext), Data("second".utf8))
    }

    private func makeKeychain(feature: String) -> MiniAppKeychain {
        MiniAppKeychain(
            context: MiniAppContext(id: MiniAppID(feature)),
            service: "test-" + UUID().uuidString
        )
    }

    private func makeAccessControl(
        flags: SecAccessControlCreateFlags
    ) throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlocked,
            flags,
            &error
        ) else {
            if let error { throw error.takeRetainedValue() }
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecParam))
        }
        return accessControl
    }

    private func setAccessControlled(
        _ data: Data,
        for account: String,
        in keychain: MiniAppKeychain,
        accessControl: SecAccessControl,
        authenticationContext: LAContext? = nil
    ) throws {
        do {
            try keychain.set(
                data,
                for: account,
                accessControl: accessControl,
                authenticationContext: authenticationContext
            )
        } catch let error as MiniAppKeychain.Failure where error.status == errSecMissingEntitlement {
            throw XCTSkip("The unsigned macOS test host cannot add a SecAccessControl-protected item")
        }
    }

    private func accessibility(for account: String, in keychain: MiniAppKeychain) throws -> String? {
        try attributes(for: account, in: keychain)?[kSecAttrAccessible as String] as? String
    }

    private func attributes(
        for account: String,
        in keychain: MiniAppKeychain,
        authenticationContext: LAContext? = nil
    ) throws -> [String: Any]? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let accessGroup = keychain.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        if let authenticationContext {
            query[kSecUseAuthenticationContext as String] = authenticationContext
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return result as? [String: Any]
    }
}
#endif
