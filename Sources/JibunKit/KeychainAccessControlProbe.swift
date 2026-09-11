// Included only by the isolated device-QA branch, never by a product build.
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
    private struct ReadOutcome {
        let status: OSStatus
        let data: Data?
    }

    private struct AttributesOutcome {
        let status: OSStatus
        let attributes: [String: Any]?
    }

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
        // A protected item can survive a cancelled or interrupted authentication.
        // Isolate every device run so stale probe data cannot collide with a retry.
        let service = "device-access-control-\(UUID().uuidString)"
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

        do {
            let unlocked = try makeAccessControl(flags: [])
            try controlled.set(Data("before".utf8), for: "value", accessControl: unlocked)
            try controlled.set(Data("after".utf8), for: "value")
            guard try controlled.data(for: "value") == Data("after".utf8) else {
                return "failed: stage=unprotected-read data-only update was not saved"
            }
            guard try accessibility(for: "value", in: controlled) == kSecAttrAccessibleWhenUnlocked as String else {
                return "failed: stage=unprotected-attributes data-only update changed protection"
            }
        } catch {
            return "failed: stage=unprotected-setup error=\(error)"
        }

        let baselineAccount = "native-baseline"
        let original = Data("original".utf8)
        let replacement = Data("replacement".utf8)
        let wrappedAccess: SecAccessControl
        let baselineAccess: SecAccessControl
        do {
            wrappedAccess = try makeAccessControl(flags: .userPresence)
            baselineAccess = try makeAccessControl(flags: .userPresence)
        } catch {
            return "failed: stage=make-user-presence-access-control error=\(error)"
        }
        let nonInteractiveWrappedAdd = wrappedAddStatus(
            original, account: "same-account", in: protected,
            accessControl: wrappedAccess, authenticationContext: nonInteractiveContext()
        )
        let nonInteractiveNativeAdd = nativeAddStatus(
            original, account: baselineAccount, in: protected,
            accessControl: baselineAccess, authenticationContext: nonInteractiveContext()
        )
        guard nonInteractiveWrappedAdd == nonInteractiveNativeAdd else {
            return "failed: stage=noninteractive-add-diverged wrapper=\(nonInteractiveWrappedAdd) native=\(nonInteractiveNativeAdd)"
        }
        let addResult: String
        if nonInteractiveWrappedAdd == errSecSuccess {
            addResult = "noninteractive-success"
        } else if isAuthenticationRejection(nonInteractiveWrappedAdd) {
            let wrappedInteractiveAdd = wrappedAddStatus(
                original, account: "same-account", in: protected,
                accessControl: wrappedAccess,
                authenticationContext: interactiveContext(reason: "Create the protected JibunKit test item")
            )
            let nativeInteractiveAdd = nativeAddStatus(
                original, account: baselineAccount, in: protected,
                accessControl: baselineAccess,
                authenticationContext: interactiveContext(reason: "Create the protected native comparison item")
            )
            guard wrappedInteractiveAdd == nativeInteractiveAdd,
                  wrappedInteractiveAdd == errSecSuccess else {
                return "failed: stage=interactive-add initial=\(nonInteractiveWrappedAdd) wrapper=\(wrappedInteractiveAdd) native=\(nativeInteractiveAdd)"
            }
            addResult = "interactive-after-\(nonInteractiveWrappedAdd)"
        } else {
            return "failed: stage=noninteractive-add wrapper=\(nonInteractiveWrappedAdd) native=\(nonInteractiveNativeAdd)"
        }

        do {
            try other.set(
                Data("other".utf8),
                for: "same-account",
                authenticationContext: nonInteractiveContext()
            )
        } catch {
            return "failed: stage=other-owner-setup error=\(error)"
        }

        let wrappedRead = wrappedReadStatus(account: "same-account", in: protected)
        let baselineRead = nativeReadStatus(account: baselineAccount, in: protected)
        guard isAuthenticationRejection(wrappedRead), isAuthenticationRejection(baselineRead) else {
            return "failed: stage=protected-read wrapper=\(wrappedRead) native=\(baselineRead) add=\(addResult)"
        }

        let wrappedBefore = attributesOutcome(
            for: "same-account", in: protected, authenticationContext: nonInteractiveContext()
        )
        let baselineBefore = attributesOutcome(
            for: baselineAccount, in: protected, authenticationContext: nonInteractiveContext()
        )
        guard wrappedBefore.status == baselineBefore.status else {
            return "failed: stage=attributes-before-diverged wrapper=\(wrappedBefore.status) native=\(baselineBefore.status)"
        }
        guard wrappedBefore.status == errSecSuccess || isAuthenticationRejection(wrappedBefore.status) else {
            return "failed: stage=attributes-before wrapper=\(wrappedBefore.status) native=\(baselineBefore.status)"
        }
        let attributeResult = wrappedBefore.status == errSecSuccess
            ? "available" : "rejected-\(wrappedBefore.status)"

        let wrappedUpdate = wrappedUpdateStatus(replacement, account: "same-account", in: protected)
        let baselineUpdate = SecItemUpdate(query(
            account: baselineAccount,
            in: protected,
            authenticationContext: nonInteractiveContext()
        ) as CFDictionary, [kSecValueData as String: replacement] as CFDictionary)
        let wrapperAllowed = wrappedUpdate == errSecSuccess
        let baselineAllowed = baselineUpdate == errSecSuccess
        guard wrapperAllowed == baselineAllowed else {
            return "failed: update diverged wrapper=\(wrappedUpdate) native=\(baselineUpdate)"
        }
        if !wrapperAllowed,
           (!isAuthenticationRejection(wrappedUpdate) || !isAuthenticationRejection(baselineUpdate)) {
            return "failed: unexpected update wrapper=\(wrappedUpdate) native=\(baselineUpdate)"
        }

        let wrappedAfter = attributesOutcome(
            for: "same-account", in: protected, authenticationContext: nonInteractiveContext()
        )
        let baselineAfter = attributesOutcome(
            for: baselineAccount, in: protected, authenticationContext: nonInteractiveContext()
        )
        guard wrappedAfter.status == baselineAfter.status else {
            return "failed: stage=attributes-after-diverged wrapper=\(wrappedAfter.status) native=\(baselineAfter.status)"
        }
        guard wrappedAfter.status == errSecSuccess || isAuthenticationRejection(wrappedAfter.status) else {
            return "failed: stage=attributes-after wrapper=\(wrappedAfter.status) native=\(baselineAfter.status)"
        }
        if !wrapperAllowed,
           wrappedBefore.status == errSecSuccess,
           wrappedAfter.status == errSecSuccess {
            guard let wrappedDateBefore = modificationDate(wrappedBefore.attributes),
                  let wrappedDateAfter = modificationDate(wrappedAfter.attributes),
                  let baselineDateBefore = modificationDate(baselineBefore.attributes),
                  let baselineDateAfter = modificationDate(baselineAfter.attributes) else {
                return "failed: stage=rejected-update-dates unavailable"
            }
            guard wrappedDateBefore == wrappedDateAfter,
                  baselineDateBefore == baselineDateAfter
            else {
                return "failed: stage=rejected-update-dates modified"
            }
        }
        guard isAuthenticationRejection(wrappedReadStatus(account: "same-account", in: protected)) else {
            return "failed: wrapper update weakened protected read"
        }
        guard isAuthenticationRejection(nativeReadStatus(account: baselineAccount, in: protected)) else {
            return "failed: native update weakened protected read"
        }

        let verificationContext = interactiveContext(reason: "Verify the protected item was retained")
        let wrappedVerified = wrappedReadOutcome(
            account: "same-account", in: protected, authenticationContext: verificationContext
        )
        let baselineVerified = nativeReadOutcome(
            account: baselineAccount, in: protected, authenticationContext: verificationContext
        )
        guard wrappedVerified.status == baselineVerified.status,
              wrappedVerified.status == errSecSuccess else {
            return "failed: stage=interactive-retention-read wrapper=\(wrappedVerified.status) native=\(baselineVerified.status)"
        }
        let expectedData = wrapperAllowed ? replacement : original
        guard wrappedVerified.data == expectedData, baselineVerified.data == expectedData else {
            return "failed: stage=interactive-retention-value wrapper=\(String(decoding: wrappedVerified.data ?? Data(), as: UTF8.self)) native=\(String(decoding: baselineVerified.data ?? Data(), as: UTF8.self))"
        }
        do {
            guard try other.data(
                for: "same-account",
                authenticationContext: nonInteractiveContext()
            ) == Data("other".utf8) else {
                return "failed: stage=other-owner-read value-changed"
            }
        } catch {
            return "failed: stage=other-owner-read error=\(error)"
        }
        let updateResult = wrapperAllowed ? "native-allowed" : "rejected-\(wrappedUpdate)"
        return "passed: update=after protected-read=rejected protected-add=\(addResult) protected-attributes=\(attributeResult) protected-update=\(updateResult) protected=present other=other"
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

    private static func interactiveContext(reason: String) -> LAContext {
        let context = LAContext()
        context.localizedReason = reason
        return context
    }

    private static func isAuthenticationRejection(_ status: OSStatus) -> Bool {
        status == errSecInteractionNotAllowed || status == errSecAuthFailed
    }

    private static func modificationDate(_ attributes: [String: Any]?) -> Date? {
        attributes?[kSecAttrModificationDate as String] as? Date
    }

    private static func wrappedReadStatus(account: String, in keychain: MiniAppKeychain) -> OSStatus {
        wrappedReadOutcome(
            account: account,
            in: keychain,
            authenticationContext: nonInteractiveContext()
        ).status
    }

    private static func wrappedReadOutcome(
        account: String,
        in keychain: MiniAppKeychain,
        authenticationContext: LAContext
    ) -> ReadOutcome {
        do {
            let data = try keychain.data(for: account, authenticationContext: authenticationContext)
            return ReadOutcome(status: errSecSuccess, data: data)
        } catch let failure as MiniAppKeychain.Failure {
            return ReadOutcome(status: failure.status, data: nil)
        } catch {
            return ReadOutcome(status: errSecInternalError, data: nil)
        }
    }

    private static func wrappedAddStatus(
        _ data: Data,
        account: String,
        in keychain: MiniAppKeychain,
        accessControl: SecAccessControl,
        authenticationContext: LAContext
    ) -> OSStatus {
        do {
            try keychain.set(
                data,
                for: account,
                accessControl: accessControl,
                authenticationContext: authenticationContext
            )
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
        nativeReadOutcome(
            account: account,
            in: keychain,
            authenticationContext: nonInteractiveContext()
        ).status
    }

    private static func nativeReadOutcome(
        account: String,
        in keychain: MiniAppKeychain,
        authenticationContext: LAContext
    ) -> ReadOutcome {
        var nativeQuery = query(account: account, in: keychain, authenticationContext: authenticationContext)
        nativeQuery[kSecReturnData as String] = true
        nativeQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(nativeQuery as CFDictionary, &result)
        return ReadOutcome(status: status, data: result as? Data)
    }

    private static func nativeAddStatus(
        _ data: Data,
        account: String,
        in keychain: MiniAppKeychain,
        accessControl: SecAccessControl,
        authenticationContext: LAContext
    ) -> OSStatus {
        SecItemAdd(item(
            account: account,
            in: keychain,
            data: data,
            accessControl: accessControl,
            authenticationContext: authenticationContext
        ) as CFDictionary, nil)
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

    private static func attributesOutcome(
        for account: String,
        in keychain: MiniAppKeychain,
        authenticationContext: LAContext
    ) -> AttributesOutcome {
        var attributesQuery = query(
            account: account,
            in: keychain,
            authenticationContext: authenticationContext
        )
        attributesQuery[kSecReturnAttributes as String] = true
        attributesQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributesQuery as CFDictionary, &result)
        return AttributesOutcome(status: status, attributes: result as? [String: Any])
    }
}
#endif
