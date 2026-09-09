import Foundation
import CryptoKit

public extension MiniAppContext {
    /// Stable on every launch. Changing this derivation would require data migration.
    func websiteDataStoreIdentifier(profile: String = "default") -> UUID {
        let seed = "jibunkit.webdata.v1\u{0}" + id.rawValue + "\u{0}" + profile
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80 // UUID version 8, application-defined derivation
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

#if canImport(WebKit)
import WebKit

public extension MiniAppContext {
    @available(macOS 14.0, iOS 17.0, *)
    @MainActor
    func websiteDataStore(profile: String = "default") -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: websiteDataStoreIdentifier(profile: profile))
    }
}
#endif
