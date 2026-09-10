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
        let contextWithoutUI = LAContext()
        contextWithoutUI.interactionNotAllowed = true
        defer {
            try? controlled.removeAll(authenticationContext: contextWithoutUI)
            try? protected.removeAll(authenticationContext: contextWithoutUI)
            try? other.removeAll(authenticationContext: contextWithoutUI)
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

        let userPresence = try makeAccessControl(flags: .userPresence)
        try protected.set(
            Data("original".utf8),
            for: "same-account",
            accessControl: userPresence,
            authenticationContext: contextWithoutUI
        )
        try other.set(Data("other".utf8), for: "same-account", authenticationContext: contextWithoutUI)

        let rejection: OSStatus
        do {
            try protected.set(
                Data("replacement".utf8),
                for: "same-account",
                authenticationContext: contextWithoutUI
            )
            return "unsupported: user-presence update succeeded without authentication"
        } catch let failure as MiniAppKeychain.Failure {
            rejection = failure.status
        }
        guard rejection == errSecInteractionNotAllowed || rejection == errSecAuthFailed else {
            return "failed: unexpected non-interactive status \(rejection)"
        }
        guard try attributes(for: "same-account", in: protected, authenticationContext: contextWithoutUI) != nil else {
            return "failed: protected item disappeared after rejected update"
        }
        guard try other.data(for: "same-account", authenticationContext: contextWithoutUI) == Data("other".utf8) else {
            return "failed: other owner changed"
        }
        return "passed: update=after rejection=\(rejection) protected=present other=other"
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
