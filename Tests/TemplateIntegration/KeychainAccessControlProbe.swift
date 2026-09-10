// Copied only into the isolated CI host, never into a distributed IPA.
#if os(iOS)
import Foundation
import LocalAuthentication
import Security
import SwiftUI
import JibunKitCore

@MainActor
enum KeychainAccessControlProbe {
    static let definition = MiniAppDefinition(
        id: MiniAppID("keychain-access-control-probe"),
        title: "Keychain access control",
        systemImage: "lock.shield"
    ) { context in
        KeychainAccessControlProbeView(context: context)
    }
}

private struct KeychainAccessControlProbeView: View {
    let context: MiniAppContext
    @State private var result = "ready"

    var body: some View {
        VStack {
            Text(result)
                .accessibilityIdentifier("keychain.access-control.result")
            Button("Run access-control probe") {
                result = "running"
                Task {
                    result = await KeychainAccessControlProbeRunner.run(context: context)
                }
            }
            .accessibilityIdentifier("keychain.access-control.run")
        }
        .navigationTitle("Keychain access control")
    }
}

private enum KeychainAccessControlProbeRunner {
    static func run(context: MiniAppContext) async -> String {
        await Task.detached {
            do {
                return try execute(context: context)
            } catch {
                return "failed: \(error)"
            }
        }.value
    }

    private static func execute(context: MiniAppContext) throws -> String {
        let service = "ci-access-control"
        let controlled = MiniAppKeychain(context: context, service: service)
        let protected = MiniAppKeychain(context: context, service: service + "-protected")
        let other = MiniAppKeychain(
            context: MiniAppContext(id: MiniAppID("keychain-access-control-other")),
            service: service + "-protected"
        )
        let cleanupContext = nonInteractiveContext()
        defer {
            try? controlled.removeAll(authenticationContext: cleanupContext)
            try? protected.removeAll(authenticationContext: cleanupContext)
            try? other.removeAll(authenticationContext: cleanupContext)
        }

        let unlocked = try makeAccessControl(flags: [])
        try controlled.set(Data("before".utf8), for: "value", accessControl: unlocked)
        try controlled.set(Data("after".utf8), for: "value")
        guard try controlled.data(for: "value") == Data("after".utf8) else {
            return "failed: data-only update was not saved"
        }
        guard try accessibility(for: "value", in: controlled) == kSecAttrAccessibleWhenUnlocked as String else {
            return "failed: data-only update changed protection"
        }

        let applicationPassword = try makeAccessControl(flags: [.userPresence, .applicationPassword])
        let creationContext = try applicationPasswordContext()
        try protected.set(
            Data("original".utf8),
            for: "same-account",
            accessControl: applicationPassword,
            authenticationContext: creationContext
        )
        let baselineAccount = "native-baseline"
        let baselineAdd = SecItemAdd(item(
            account: baselineAccount,
            in: protected,
            data: Data("original".utf8),
            accessControl: try makeAccessControl(flags: [.userPresence, .applicationPassword]),
            authenticationContext: try applicationPasswordContext()
        ) as CFDictionary, nil)
        guard baselineAdd == errSecSuccess else {
            return "failed: native baseline add status \(baselineAdd)"
        }
        try other.set(
            Data("other".utf8),
            for: "same-account",
            authenticationContext: nonInteractiveContext()
        )

        let wrappedRead = wrappedReadStatus(account: "same-account", in: protected)
        let baselineRead = nativeReadStatus(account: baselineAccount, in: protected)
        guard isAuthenticationRejection(wrappedRead), isAuthenticationRejection(baselineRead) else {
            return "failed: protected read wrapper=\(wrappedRead) native=\(baselineRead)"
        }

        let wrappedBefore = try attributes(for: "same-account", in: protected, authenticationContext: nonInteractiveContext())
        let baselineBefore = try attributes(for: baselineAccount, in: protected, authenticationContext: nonInteractiveContext())
        let wrappedUpdate = wrappedUpdateStatus(Data("replacement".utf8), account: "same-account", in: protected)
        let baselineUpdate = SecItemUpdate(query(
            account: baselineAccount,
            in: protected,
            authenticationContext: nonInteractiveContext()
        ) as CFDictionary, [kSecValueData as String: Data("replacement".utf8)] as CFDictionary)
        let wrapperAllowed = wrappedUpdate == errSecSuccess
        let baselineAllowed = baselineUpdate == errSecSuccess
        guard wrapperAllowed == baselineAllowed else {
            return "failed: update diverged wrapper=\(wrappedUpdate) native=\(baselineUpdate)"
        }
        if !wrapperAllowed,
           (!isAuthenticationRejection(wrappedUpdate) || !isAuthenticationRejection(baselineUpdate)) {
            return "failed: unexpected update wrapper=\(wrappedUpdate) native=\(baselineUpdate)"
        }

        let wrappedAfter = try attributes(for: "same-account", in: protected, authenticationContext: nonInteractiveContext())
        let baselineAfter = try attributes(for: baselineAccount, in: protected, authenticationContext: nonInteractiveContext())
        guard wrappedAfter != nil, baselineAfter != nil else {
            return "failed: protected item disappeared after update attempt"
        }
        if !wrapperAllowed {
            guard let wrappedDateBefore = modificationDate(wrappedBefore),
                  let wrappedDateAfter = modificationDate(wrappedAfter),
                  let baselineDateBefore = modificationDate(baselineBefore),
                  let baselineDateAfter = modificationDate(baselineAfter)
            else {
                return "failed: rejected update item dates unavailable"
            }
            guard wrappedDateBefore == wrappedDateAfter,
                  baselineDateBefore == baselineDateAfter
            else {
                return "failed: rejected update modified an item"
            }
        }
        guard isAuthenticationRejection(wrappedReadStatus(account: "same-account", in: protected)) else {
            return "failed: wrapper update weakened protected read"
        }
        guard isAuthenticationRejection(nativeReadStatus(account: baselineAccount, in: protected)) else {
            return "failed: native update weakened protected read"
        }
        guard try other.data(
            for: "same-account",
            authenticationContext: nonInteractiveContext()
        ) == Data("other".utf8) else {
            return "failed: other owner changed"
        }
        let updateResult = wrapperAllowed ? "native-allowed" : "rejected-\(wrappedUpdate)"
        return "passed: update=after protected-read=rejected protected-update=\(updateResult) protected=present other=other"
    }

    private static func makeAccessControl(
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

    private static func applicationPasswordContext() throws -> LAContext {
        let context = nonInteractiveContext()
        guard context.setCredential(Data("ci-password".utf8), type: .applicationPassword) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecAuthFailed))
        }
        return context
    }

    private static func accessibility(
        for account: String,
        in keychain: MiniAppKeychain
    ) throws -> String? {
        try attributes(for: account, in: keychain)?[kSecAttrAccessible as String] as? String
    }

    private static func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    private static func isAuthenticationRejection(_ status: OSStatus) -> Bool {
        status == errSecInteractionNotAllowed || status == errSecAuthFailed
    }

    private static func modificationDate(_ attributes: [String: Any]?) -> Date? {
        attributes?[kSecAttrModificationDate as String] as? Date
    }

    private static func wrappedReadStatus(account: String, in keychain: MiniAppKeychain) -> OSStatus {
        do {
            _ = try keychain.data(for: account, authenticationContext: nonInteractiveContext())
            return errSecSuccess
        } catch let failure as MiniAppKeychain.Failure {
            return failure.status
        } catch {
            return errSecInternalError
        }
    }

    private static func wrappedUpdateStatus(
        _ data: Data,
        account: String,
        in keychain: MiniAppKeychain
    ) -> OSStatus {
        do {
            try keychain.set(data, for: account, authenticationContext: nonInteractiveContext())
            return errSecSuccess
        } catch let failure as MiniAppKeychain.Failure {
            return failure.status
        } catch {
            return errSecInternalError
        }
    }

    private static func nativeReadStatus(account: String, in keychain: MiniAppKeychain) -> OSStatus {
        var nativeQuery = query(account: account, in: keychain, authenticationContext: nonInteractiveContext())
        nativeQuery[kSecReturnData as String] = true
        nativeQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(nativeQuery as CFDictionary, nil)
    }

    private static func item(
        account: String,
        in keychain: MiniAppKeychain,
        data: Data,
        accessControl: SecAccessControl,
        authenticationContext: LAContext
    ) -> [String: Any] {
        var item = query(account: account, in: keychain, authenticationContext: authenticationContext)
        item[kSecValueData as String] = data
        item[kSecAttrAccessControl as String] = accessControl
        return item
    }

    private static func query(
        account: String,
        in keychain: MiniAppKeychain,
        authenticationContext: LAContext
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseAuthenticationContext as String: authenticationContext,
        ]
        if let accessGroup = keychain.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private static func attributes(
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
