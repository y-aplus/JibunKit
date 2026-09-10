import Foundation

extension MiniAppRuntime {
    func makeWebAuthentication(
        context: MiniAppContext,
        coordinator: MiniAppWebAuthenticationCoordinator,
        provider: any MiniAppWebAuthenticationSessionProviding
    ) throws -> MiniAppWebAuthentication {
        let authentication = MiniAppWebAuthentication(
            context: context, coordinator: coordinator, provider: provider)
        try onShutdown { authentication.close() }
        return authentication
    }
}

#if canImport(AuthenticationServices)
import AuthenticationServices

@MainActor
private final class ASWebAuthenticationSessionProvider: MiniAppWebAuthenticationSessionProviding {
    private let presentationContextProvider: any ASWebAuthenticationPresentationContextProviding
    private let prefersEphemeralWebBrowserSession: Bool

    init(
        presentationContextProvider: any ASWebAuthenticationPresentationContextProviding,
        prefersEphemeralWebBrowserSession: Bool
    ) {
        self.presentationContextProvider = presentationContextProvider
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
    }

    func makeSession(
        url: URL,
        callbackURLScheme: String?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) -> any MiniAppWebAuthenticationSession {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme) {
            callbackURL, error in
            Task { @MainActor in
                if let callbackURL { completion(.success(callbackURL)) }
                else if let error { completion(.failure(error)) }
                else { completion(.failure(MiniAppWebAuthenticationCoordinator.Failure.missingCallbackURL)) }
            }
        }
        session.presentationContextProvider = presentationContextProvider
        session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        return session
    }
}

@available(iOS 17.4, macOS 14.4, *)
@MainActor
private final class ASWebAuthenticationCallbackProvider: MiniAppWebAuthenticationSessionProviding {
    private let callback: ASWebAuthenticationSession.Callback
    private let presentationContextProvider: any ASWebAuthenticationPresentationContextProviding
    private let prefersEphemeralWebBrowserSession: Bool

    init(
        callback: ASWebAuthenticationSession.Callback,
        presentationContextProvider: any ASWebAuthenticationPresentationContextProviding,
        prefersEphemeralWebBrowserSession: Bool
    ) {
        self.callback = callback
        self.presentationContextProvider = presentationContextProvider
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
    }

    func makeSession(
        url: URL,
        callbackURLScheme: String?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) -> any MiniAppWebAuthenticationSession {
        let session = ASWebAuthenticationSession(url: url, callback: callback) {
            callbackURL, error in
            Task { @MainActor in
                if let callbackURL { completion(.success(callbackURL)) }
                else if let error { completion(.failure(error)) }
                else { completion(.failure(MiniAppWebAuthenticationCoordinator.Failure.missingCallbackURL)) }
            }
        }
        session.presentationContextProvider = presentationContextProvider
        session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        return session
    }
}

extension ASWebAuthenticationSession: MiniAppWebAuthenticationSession {}

public extension MiniAppRuntime {
    func makeWebAuthentication(
        context: MiniAppContext,
        coordinator: MiniAppWebAuthenticationCoordinator,
        presentationContextProvider: any ASWebAuthenticationPresentationContextProviding,
        prefersEphemeralWebBrowserSession: Bool = false
    ) throws -> MiniAppWebAuthentication {
        try makeWebAuthentication(
            context: context,
            coordinator: coordinator,
            provider: ASWebAuthenticationSessionProvider(
                presentationContextProvider: presentationContextProvider,
                prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession))
    }
}

@available(iOS 17.4, macOS 14.4, *)
public extension MiniAppWebAuthentication {
    /// Uses Apple's native callback descriptor, including associated HTTPS
    /// callbacks, without reducing it to a custom URL scheme.
    @discardableResult
    func start(
        url: URL,
        callback: ASWebAuthenticationSession.Callback,
        presentationContextProvider: any ASWebAuthenticationPresentationContextProviding,
        prefersEphemeralWebBrowserSession: Bool = false,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) throws -> MiniAppWebAuthenticationRequest {
        try start(
            url: url,
            provider: ASWebAuthenticationCallbackProvider(
                callback: callback,
                presentationContextProvider: presentationContextProvider,
                prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession),
            completion: completion)
    }
}
#endif
