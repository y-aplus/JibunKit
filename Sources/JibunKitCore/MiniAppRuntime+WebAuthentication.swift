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
#endif
