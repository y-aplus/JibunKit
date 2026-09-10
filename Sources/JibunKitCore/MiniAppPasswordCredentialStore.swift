#if canImport(Security)
import Foundation

/// Explicit password persistence for one Feature/profile. Retain one live owner
/// and quiesce its URLSessions before reload/clear. This is not a trust policy.
@MainActor
public final class MiniAppPasswordCredentialStore {
    public enum Failure: Error, Equatable { case invalidArchive, unsupportedVersion, unsupportedCredential }
    public let storage: URLCredentialStorage
    private let keychain: MiniAppKeychain
    private let account: String

    public init(context: MiniAppContext, profile: String = "default") throws {
        guard let storage = URLSessionConfiguration.ephemeral.urlCredentialStorage else {
            throw Failure.unsupportedCredential
        }
        self.storage = storage
        keychain = MiniAppKeychain(context: context, service: "network-passwords-v1")
        account = profile
        try reload()
    }

    /// Explicitly persists every password in this private store, including
    /// forSession credentials. The native shared store is never consulted.
    /// Identity/trust credentials cannot be represented by this password adapter.
    public func save() throws {
        var spaces: [Space] = []
        for (space, credentials) in storage.allCredentials {
            var passwords: [Password] = []
            for (user, credential) in credentials {
                guard credential.hasPassword, credential.user == user, let password = credential.password else {
                    throw Failure.unsupportedCredential
                }
                passwords.append(Password(user: user, password: password))
            }
            let saved = Space(protection: Protection(space), passwords: passwords,
                              defaultUser: storage.defaultCredential(for: space)?.user)
            guard saved.protection.makeSpace() == space else { throw Failure.unsupportedCredential }
            spaces.append(saved)
        }
        let archive = Archive(version: 1, spaces: spaces)
        // Validate the complete snapshot before replacing the previous Keychain item.
        _ = try archive.validated()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try keychain.set(encoder.encode(archive), for: account)
    }

    /// Failure preserves both the live store and the saved data. Requests must
    /// be stopped: replacing credentials does not revoke an existing connection.
    public func reload() throws {
        let entries: [(URLProtectionSpace, [URLCredential], String?)]
        if let data = try keychain.data(for: account) {
            let archive: Archive
            do { archive = try PropertyListDecoder().decode(Archive.self, from: data) }
            catch { throw Failure.invalidArchive }
            entries = try archive.validated()
        } else { entries = [] }
        removeLiveCredentials()
        for (space, credentials, defaultUser) in entries {
            for credential in credentials { storage.set(credential, for: space) }
            if let credential = credentials.first(where: { $0.user == defaultUser }) {
                storage.setDefaultCredential(credential, for: space)
            }
        }
    }

    /// Stop/invalidate sessions first; cached authentication and late delegate
    /// callbacks are outside this store. Deletion failure leaves live data intact.
    public func clear() throws {
        try keychain.remove(account: account)
        removeLiveCredentials()
    }

    private func removeLiveCredentials() {
        for (space, credentials) in storage.allCredentials {
            for credential in credentials.values { storage.remove(credential, for: space) }
        }
    }

    private struct Archive: Codable {
        let version: Int
        let spaces: [Space]

        func validated() throws -> [(URLProtectionSpace, [URLCredential], String?)] {
            guard version == 1 else { throw Failure.unsupportedVersion }
            var seen = Set<URLProtectionSpace>()
            return try spaces.map { entry in
                guard (0...65535).contains(entry.protection.port) else { throw Failure.invalidArchive }
                let space = entry.protection.makeSpace()
                guard Protection(space) == entry.protection,
                      seen.insert(space).inserted else { throw Failure.invalidArchive }
                let users = Set(entry.passwords.map(\.user))
                guard users.count == entry.passwords.count,
                      entry.defaultUser.map({ users.contains($0) }) ?? true else { throw Failure.invalidArchive }
                // Never hand Foundation a permanent/synchronizable credential:
                // persistence belongs exclusively to the scoped Keychain item.
                let credentials = entry.passwords.map {
                    URLCredential(user: $0.user, password: $0.password, persistence: .forSession)
                }
                return (space, credentials, entry.defaultUser)
            }
        }
    }

    private struct Space: Codable {
        let protection: Protection
        let passwords: [Password]
        let defaultUser: String?
    }

    private struct Password: Codable {
        let user: String
        let password: String
    }

    private struct Protection: Codable, Equatable {
        let host: String
        let port: Int
        let scheme: String?
        let realm: String?
        let authenticationMethod: String
        let isProxy: Bool
        let proxyType: String?

        init(_ space: URLProtectionSpace) {
            host = space.host
            port = space.port
            scheme = space.protocol
            realm = space.realm
            authenticationMethod = space.authenticationMethod
            isProxy = space.isProxy()
            proxyType = space.proxyType
        }

        func makeSpace() -> URLProtectionSpace {
            if isProxy {
                return URLProtectionSpace(proxyHost: host, port: port, type: proxyType,
                    realm: realm, authenticationMethod: authenticationMethod)
            }
            return URLProtectionSpace(host: host, port: port, protocol: scheme,
                realm: realm, authenticationMethod: authenticationMethod)
        }
    }
}
#endif
