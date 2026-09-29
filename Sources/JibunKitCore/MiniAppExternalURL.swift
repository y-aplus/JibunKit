import Foundation
#if os(iOS)
import UIKit
#endif

public enum MiniAppExternalURLError: Error, Equatable, Sendable, LocalizedError {
    case invalidURL
    case inactive
    case rejected

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Only another app's URL with an explicit scheme can be opened (invalidURL)."
        case .inactive: "The app did not become active before the external URL could be opened (inactive)."
        case .rejected: "The system did not open the external URL (rejected)."
        }
    }
}

/// Opens another app from a Feature. The host owns scene activation, so a
/// request made while JibunKit is still launching or returning from Spotlight
/// waits for the app to become active instead of being dropped by the system.
public enum MiniAppExternalURL {
    /// Rejects file URLs, JibunKit's own routing scheme and URLs without a
    /// scheme. Whether a target app is installed is decided by the system.
    public static func validate(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty,
              !url.isFileURL, scheme != "jibunkit" else { throw MiniAppExternalURLError.invalidURL }
    }

    #if os(iOS)
    /// Waits up to `activationTimeout` for the app to become active, then asks
    /// the system to open `url`. Throws instead of silently doing nothing.
    @MainActor
    public static func open(_ url: URL, activationTimeout: Duration = .seconds(5)) async throws {
        try validate(url)
        let deadline = ContinuousClock.now + activationTimeout
        // Polling keeps the wait cancellable and free of observer bookkeeping;
        // the interval is far below what a user can perceive.
        while UIApplication.shared.applicationState != .active {
            guard ContinuousClock.now < deadline else { throw MiniAppExternalURLError.inactive }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard await UIApplication.shared.open(url) else { throw MiniAppExternalURLError.rejected }
    }
    #endif
}
