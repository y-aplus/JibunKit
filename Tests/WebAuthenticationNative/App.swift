import AuthenticationServices
import JibunKitCore
import SwiftUI
import UIKit

@main
struct WebAuthenticationNativeProbeApp: App {
    @StateObject private var model = AuthenticationModel()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 24) {
                Button("Baseline Complete") { model.startBaseline(path: "complete") }
                    .accessibilityIdentifier("baseline.complete")
                Button("Baseline Cancel") { model.startBaseline(path: "hold") }
                    .accessibilityIdentifier("baseline.cancel")
                Button("Wrapper Complete") { model.startWrapper(path: "complete") }
                    .accessibilityIdentifier("wrapper.complete")
                Button("Wrapper Cancel") { model.startWrapper(path: "hold") }
                    .accessibilityIdentifier("wrapper.cancel")
                Text(model.status).accessibilityIdentifier("auth.status")
            }
        }
    }
}

@MainActor
private final class AuthenticationModel: NSObject, ObservableObject,
    ASWebAuthenticationPresentationContextProviding {
    @Published var status = "idle"
    private var session: ASWebAuthenticationSession?
    private var request: MiniAppWebAuthenticationRequest?
    private let runtime = MiniAppRuntime()
    private let coordinator = MiniAppWebAuthenticationCoordinator()
    private var authentication: MiniAppWebAuthentication?

    func startBaseline(path: String) {
        status = "starting"
        let url = URL(string: "http://127.0.0.1:8765/\(path)")!
        let session = ASWebAuthenticationSession(
            url: url, callbackURLScheme: "jibunkit-auth-probe"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in self?.complete(callbackURL, error: error) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        self.session = session
        status = session.start() ? "presented" : "rejected"
    }

    func startWrapper(path: String) {
        status = "starting"
        do {
            let authentication: MiniAppWebAuthentication
            if let existing = self.authentication { authentication = existing }
            else {
                authentication = try runtime.makeWebAuthentication(
                    context: MiniAppContext(id: MiniAppID("native-probe")),
                    coordinator: coordinator,
                    presentationContextProvider: self,
                    prefersEphemeralWebBrowserSession: true)
                self.authentication = authentication
            }
            request = try authentication.start(
                url: URL(string: "http://127.0.0.1:8765/\(path)")!,
                callback: .customScheme("jibunkit-auth-probe"),
                presentationContextProvider: self,
                prefersEphemeralWebBrowserSession: true
            ) { [weak self] result in
                switch result {
                case let .success(url): self?.complete(url, error: nil)
                case let .failure(error): self?.complete(nil, error: error)
                }
            }
            status = "presented"
        } catch { status = "failed" }
    }

    private func complete(_ callbackURL: URL?, error: Error?) {
        if callbackURL?.host == "callback" { status = "completed" }
        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
            status = "cancelled"
        } else if error as? MiniAppWebAuthenticationCoordinator.Failure == .cancelled {
            status = "cancelled"
        } else { status = "failed" }
        session = nil
        request = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first.map(UIWindow.init(windowScene:))
            ?? ASPresentationAnchor()
    }
}
