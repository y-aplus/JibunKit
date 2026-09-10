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
            Button("Write page storage") {
                perform("return await window.jibunKitWrite(value)", arguments: ["value": context.id.rawValue])
            }
                .disabled(!pageReady)
                .accessibilityIdentifier("web-storage.write")
            Button("Read page storage") {
                perform("return await window.jibunKitRead()")
            }
                .disabled(!pageReady)
                .accessibilityIdentifier("web-storage.read")
            Button("Clear this owner") {
                operation += 1
                let token = operation
                result = "clearing"
                Task {
                    await webView.configuration.websiteDataStore.removeData(
                        ofTypes: [
                            WKWebsiteDataTypeCookies,
                            WKWebsiteDataTypeLocalStorage,
                            WKWebsiteDataTypeIndexedDBDatabases,
                        ],
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

    private func perform(_ body: String, arguments: [String: Any] = [:]) {
        operation += 1
        let token = operation
        result = "running"
        Task {
            do {
                let value = try await webView.callAsyncJavaScript(
                    body,
                    arguments: arguments,
                    contentWorld: .page
                )
                guard token == operation else { return }
                guard let pageResult = value as? String else {
                    result = "failed: page returned no string result"
                    return
                }
                result = pageResult
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
            webView.evaluateJavaScript("document.readyState === 'complete' && typeof window.jibunKitRead === 'function' && typeof window.jibunKitWrite === 'function'") {
                value, error in
                self.ready = error == nil && (value as? Bool == true)
            }
        }
    }

    private static let html = """
    <!doctype html><html><head><meta charset="utf-8"><title>Web storage ownership</title></head>
    <body><p id="status">ready</p><script>
    const databaseName = 'ownership-db';
    const objectStoreName = 'values';
    const objectKey = 'owner';

    function openDatabaseForWrite() {
      return new Promise((resolve, reject) => {
        const request = indexedDB.open(databaseName, 1);
        request.onupgradeneeded = () => request.result.createObjectStore(objectStoreName);
        request.onerror = () => reject(request.error);
        request.onsuccess = () => resolve(request.result);
      });
    }

    async function readIndexedDBWithoutCreating() {
      const databases = await indexedDB.databases();
      if (!databases.some(database => database.name === databaseName)) return 'missing';
      return new Promise((resolve, reject) => {
        const request = indexedDB.open(databaseName, 1);
        request.onupgradeneeded = () => {
          request.transaction.abort();
          reject(new Error('read attempted to recreate a deleted database'));
        };
        request.onerror = () => reject(request.error);
        request.onsuccess = () => {
          const database = request.result;
          let transaction;
          let get;
          let settled = false;
          const fail = error => {
            if (settled) return;
            settled = true;
            database.close();
            reject(error || new Error('IndexedDB read transaction failed'));
          };
          try {
            transaction = database.transaction(objectStoreName, 'readonly');
            get = transaction.objectStore(objectStoreName).get(objectKey);
            get.onerror = () => fail(get.error);
            transaction.onerror = () => fail(transaction.error);
            transaction.onabort = () => fail(transaction.error || new Error('IndexedDB read transaction aborted'));
            transaction.oncomplete = () => {
              if (settled) return;
              settled = true;
              const value = get.result || 'missing';
              database.close();
              resolve(value);
            };
          } catch (error) {
            fail(error);
          }
        };
      });
    }

    window.jibunKitRead = async function() {
      const local = localStorage.getItem('owner') || 'missing';
      const entry = document.cookie.split('; ').find(row => row.startsWith('owner='));
      const cookie = entry ? decodeURIComponent(entry.substring(6)) : 'missing';
      const indexeddb = await readIndexedDBWithoutCreating();
      return `local=${local} cookie=${cookie} indexeddb=${indexeddb}`;
    };

    window.jibunKitWrite = async function(value) {
      localStorage.setItem('owner', value);
      document.cookie = `owner=${encodeURIComponent(value)}; Max-Age=86400; Path=/; SameSite=Lax`;
      const database = await openDatabaseForWrite();
      await new Promise((resolve, reject) => {
        let settled = false;
        const fail = error => {
          if (settled) return;
          settled = true;
          database.close();
          reject(error || new Error('IndexedDB write transaction failed'));
        };
        try {
          const transaction = database.transaction(objectStoreName, 'readwrite');
          transaction.objectStore(objectStoreName).put(value, objectKey);
          transaction.onerror = () => fail(transaction.error);
          transaction.onabort = () => fail(transaction.error || new Error('IndexedDB write transaction aborted'));
          transaction.oncomplete = () => {
            if (settled) return;
            settled = true;
            database.close();
            resolve();
          };
        } catch (error) {
          fail(error);
        }
      });
      return await window.jibunKitRead();
    };
    </script></body></html>
    """
}
#endif
