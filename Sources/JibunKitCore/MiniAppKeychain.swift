#if canImport(Security)
import Foundation
import Security

/// Generic-password storage scoped to one Feature and service.
/// This is cooperative ownership, not a security boundary inside the host process.
public struct MiniAppKeychain: Sendable {
    public struct Failure: Error, Equatable {
        public let status: OSStatus
    }

    public let serviceIdentifier: String
    public let accessGroup: String?

    public init(context: MiniAppContext, service: String, accessGroup: String? = nil) {
        serviceIdentifier = "jibunkit.\(context.id.storageNamespace).keychain." + Data(service.utf8).base64EncodedString()
        self.accessGroup = accessGroup
    }

    private func query(account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier, kSecAttrSynchronizable as String: false]
        if let account { query[kSecAttrAccount as String] = account }
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func data(for account: String) throws -> Data? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard let data = result as? Data else { throw Failure(status: errSecDecode) }
        return data
    }

    /// Updates in place. Omit accessibility to preserve existing protection, or
    /// pass a native kSecAttrAccessible value to explicitly set/change it.
    /// New items without an explicit value use the standard when-unlocked default.
    public func set(_ data: Data, for account: String, accessibility: CFString? = nil) throws {
        let query = query(account: account)
        var changes: [String: Any] = [kSecValueData as String: data]
        if let accessibility { changes[kSecAttrAccessible as String] = accessibility }
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(changes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
            // Another caller may have inserted the same item after our update.
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
            }
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    public func remove(account: String) throws {
        try remove(query(account: account))
    }

    /// Removes every account in this Feature's service, never another service or Feature.
    public func removeAll() throws {
        try remove(query())
    }

    private func remove(_ query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
#endif
