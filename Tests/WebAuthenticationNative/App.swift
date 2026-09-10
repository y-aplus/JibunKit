import AuthenticationServices
import SwiftUI
import UIKit

@main
struct WebAuthenticationNativeProbeApp: App {
    @StateObject private var model = AuthenticationModel()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 24) {
                Button("Complete") { model.start(path: "complete") }
                    .accessibilityIdentifier("auth.complete")
                Button("Cancel") { model.start(path: "hold") }
                    .accessibilityIdentifier("auth.cancel")
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

    func start(path: String) {
        status = "starting"
        let url = URL(string: "http://127.0.0.1:8765/\(path)")!
        let session = ASWebAuthenticationSession(
            url: url, callbackURLScheme: "jibunkit-auth-probe"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                if callbackURL?.host == "callback" { self?.status = "completed" }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    self?.status = "cancelled"
                } else { self?.status = "failed" }
                self?.session = nil
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        self.session = session
        status = session.start() ? "presented" : "rejected"
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first.map(UIWindow.init(windowScene:))
            ?? ASPresentationAnchor()
    }
}
