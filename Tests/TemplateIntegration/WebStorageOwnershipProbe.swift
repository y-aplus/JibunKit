// Copied only into the isolated CI host, never into a distributed IPA.
#if os(iOS)
import JibunKitCore
import SwiftUI
import WebKit

@MainActor
enum WebStorageOwnershipProbe {
    static let ownerADefinition = definition(id: "web-storage-owner-a", title: "Web storage owner A")
    static let ownerBDefinition = definition(id: "web-storage-owner-b", title: "Web storage owner B")

    private static func definition(id: String, title: String) -> MiniAppDefinition {
        MiniAppDefinition(id: MiniAppID(id), title: title, systemImage: "globe") { context in
            WebStorageOwnershipProbeView(context: context)
        }
    }
}

private struct WebStorageOwnershipProbeView: View {
    let context: MiniAppContext
    @State private var webView: WKWebView
    @State private var pageReady = false
    @State private var result = "idle"
    @State private var operation = 0

    init(context: MiniAppContext) {
        self.context = context
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = context.websiteDataStore()
        _webView = State(initialValue: WKWebView(frame: .zero, configuration: configuration))
    }

    var body: some View {
        VStack(spacing: 12) {
            WebStoragePage(webView: webView, ready: $pageReady)
                .frame(height: 100)
            Text(pageReady ? "page-ready" : "page-loading")
                .accessibilityIdentifier("web-storage.page")
            Text(result)
                .accessibilityIdentifier("web-storage.result")
            Button("Write page storage") { perform(writeScript) }
                .disabled(!pageReady)
                .accessibilityIdentifier("web-storage.write")
            Button("Read page storage") { perform(readScript) }
                .disabled(!pageReady)
                .accessibilityIdentifier("web-storage.read")
            Button("Clear this owner") {
                operation += 1
                let token = operation
                result = "clearing"
                Task {
                    await webView.configuration.websiteDataStore.removeData(
                        ofTypes: [WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage],
                        modifiedSince: .distantPast
                    )
                    guard token == operation else { return }
                    result = "removed owner=\(context.id.rawValue)"
                }
            }
            .accessibilityIdentifier("web-storage.clear")
        }
        .padding()
        .navigationTitle(context.id.rawValue)
    }

    private var writeScript: String {
        "window.jibunKitWrite('\(context.id.rawValue)')"
    }

    private var readScript: String { "window.jibunKitRead()" }

    private func perform(_ script: String) {
        operation += 1
        let token = operation
        result = "running"
        Task {
            do {
                let value = try await webView.evaluateJavaScript(script)
                guard token == operation else { return }
                result = String(describing: value)
            } catch {
                guard token == operation else { return }
                result = "failed: \(error)"
            }
        }
    }

}

private struct WebStoragePage: UIViewRepresentable {
    let webView: WKWebView
    @Binding var ready: Bool

    func makeCoordinator() -> Coordinator { Coordinator(ready: $ready) }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        guard let origin = URL(string: "https://jibunkit.example/ownership") else {
            preconditionFailure("The fixed Web storage probe origin must be valid")
        }
        webView.loadHTMLString(Self.html, baseURL: origin)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding private var ready: Bool

        init(ready: Binding<Bool>) { _ready = ready }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.readyState === 'complete' && typeof window.jibunKitRead === 'function'") {
                value, error in
                self.ready = error == nil && (value as? Bool == true)
            }
        }
    }

    private static let html = """
    <!doctype html><html><head><meta charset="utf-8"><title>Web storage ownership</title></head>
    <body><p id="status">ready</p><script>
    window.jibunKitRead = function() {
      const local = localStorage.getItem('owner') || 'missing';
      const entry = document.cookie.split('; ').find(row => row.startsWith('owner='));
      const cookie = entry ? decodeURIComponent(entry.substring(6)) : 'missing';
      return `local=${local} cookie=${cookie}`;
    };
    window.jibunKitWrite = function(value) {
      localStorage.setItem('owner', value);
      document.cookie = `owner=${encodeURIComponent(value)}; Max-Age=86400; Path=/; SameSite=Lax`;
      return window.jibunKitRead();
    };
    </script></body></html>
    """
}
#endif
