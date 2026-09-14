// Generated validation host only. Uses ordinary Definition/lifetime/removal entry points.
#if os(iOS)
import AuthenticationServices
import JibunKitCore
import Observation
import SwiftUI
import UIKit
import WebKit

@MainActor
enum P1WebProbe {
    private static let ownerA = Owner("p1-web-a")
    private static let ownerB = Owner("p1-web-b")

    static let ownerADefinition = definition(ownerA, title: "Web検証 A")
    static let ownerBDefinition = definition(ownerB, title: "Web検証 B")

    private static func definition(_ owner: Owner, title: String) -> MiniAppDefinition {
        MiniAppDefinition(
            id: owner.id,
            title: title,
            systemImage: "globe",
            lifetime: owner.lifetime,
            removal: MiniAppRemovalProvider(
                id: owner.id,
                dataDescription: "Cookie、localStorage、IndexedDB"
            ) {
                await owner.removeData()
            }
        ) { _ in
            P1WebProbeView(owner: owner)
        }
    }
}

@MainActor
@Observable
private final class Owner {
    let id: MiniAppID
    let dataStore: WKWebsiteDataStore
    let webView: WKWebView
    var ready = false
    var result = "idle"
    var authenticationResult = "idle"
    private var writeTask: Task<Void, Never>?
    private var authentication: MiniAppWebAuthentication?
    private var authenticationRequest: MiniAppWebAuthenticationRequest?
    private let presentation = PresentationProvider()
    private static let authenticationCoordinator = MiniAppWebAuthenticationCoordinator()

    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        self.authentication = try runtime.makeWebAuthentication(
            context: MiniAppContext(id: self.id),
            coordinator: Self.authenticationCoordinator,
            presentationContextProvider: self.presentation,
            prefersEphemeralWebBrowserSession: true
        )
        try runtime.onShutdown { [weak self] in
            self?.writeTask = nil
            self?.authenticationRequest = nil
            self?.authentication = nil
        }
    }

    init(_ rawID: String) {
        id = MiniAppID(rawID)
        dataStore = MiniAppContext(id: id).websiteDataStore()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        webView = WKWebView(frame: .zero, configuration: configuration)
    }

    func write(delayMilliseconds: Int = 0, failBeforeCommit: Bool = false) {
        guard let runtime = lifetime.runtime else { result = "failed: not running"; return }
        result = delayMilliseconds == 0 ? "writing" : "write waiting"
        do {
            writeTask = try runtime.start { [weak self] in
                guard let self else { return }
                do {
                    let value = try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: self.id) {
                        try await self.evaluateWrite(
                            delayMilliseconds: delayMilliseconds, failBeforeCommit: failBeforeCommit)
                    }
                    await self.setResult(value)
                } catch is CancellationError {
                    await self.setResult("cancelled")
                } catch {
                    await self.setResult("failed: \(error)")
                }
            }
        } catch { result = "failed: closed" }
    }

    func read() {
        guard let runtime = lifetime.runtime else { result = "failed: not running"; return }
        result = "reading"
        do {
            _ = try runtime.start { [weak self] in
                guard let self else { return }
                do {
                    let value = try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: self.id) {
                        try await self.evaluateRead()
                    }
                    await self.setResult(value)
                } catch { await self.setResult("failed: \(error)") }
            }
        } catch { result = "failed: closed" }
    }

    func cancelWrite() { writeTask?.cancel() }

    func removeData() async {
        await dataStore.removeData(
            ofTypes: [WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage,
                      WKWebsiteDataTypeIndexedDBDatabases],
            modifiedSince: .distantPast
        )
    }

    func startAuthentication(path: String) {
        guard let authentication else { authenticationResult = "failed: not running"; return }
        authenticationResult = "starting"
        do {
            authenticationRequest = try authentication.start(
                url: URL(string: "http://127.0.0.1:8765/\(path)")!,
                callbackURLScheme: "jibunkit-auth-probe"
            ) { [weak self] result in
                switch result {
                case let .success(url):
                    self?.authenticationResult = url.host == "callback" ? "completed \(self?.id.rawValue ?? "missing")" : "failed: wrong callback"
                case let .failure(error as MiniAppWebAuthenticationCoordinator.Failure):
                    self?.authenticationResult = error == .cancelled ? "cancelled" : "failed: \(error)"
                case let .failure(error as ASWebAuthenticationSessionError):
                    self?.authenticationResult = error.code == .canceledLogin ? "cancelled" : "failed: \(error)"
                case let .failure(error): self?.authenticationResult = "failed: \(error)"
                }
                self?.authenticationRequest = nil
            }
            authenticationResult = "presented"
        } catch let error as MiniAppWebAuthenticationCoordinator.Failure {
            if case let .presentationBusy(owner) = error { authenticationResult = "busy: \(owner.rawValue)" }
            else { authenticationResult = "failed: \(error)" }
        } catch { authenticationResult = "failed: \(error)" }
    }

    func cancelAuthentication() { authenticationRequest?.cancel() }

    private func evaluateRead() async throws -> String {
        try Task.checkCancellation()
        let value = try await webView.callAsyncJavaScript(
            "return await window.p1Read()", arguments: [:], contentWorld: .page)
        try Task.checkCancellation()
        guard let string = value as? String else { throw ProbeFailure.nonStringResult }
        return string
    }

    private func evaluateWrite(delayMilliseconds: Int, failBeforeCommit: Bool) async throws -> String {
        try Task.checkCancellation()
        if delayMilliseconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(delayMilliseconds) * 1_000_000)
        }
        let value = try await webView.callAsyncJavaScript(
            "return await window.p1Write(value, delay)",
            arguments: ["value": id.rawValue, "delay": 0,
                        "fail": failBeforeCommit], contentWorld: .page)
        try Task.checkCancellation()
        guard let string = value as? String else { throw ProbeFailure.nonStringResult }
        return string
    }

    private func setResult(_ value: String) { result = value; writeTask = nil }
    private enum ProbeFailure: Error { case nonStringResult }
}

@MainActor
private final class PresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first.map(UIWindow.init(windowScene:)) ?? ASPresentationAnchor()
    }
}

private struct P1WebProbeView: View {
    @Bindable var owner: Owner

    var body: some View {
        List {
            WebPage(owner: owner).frame(height: 100)
            Text(owner.ready ? "page-ready" : "page-loading").accessibilityIdentifier("p1.web.page")
            Text(owner.result).accessibilityIdentifier("p1.web.result")
            Button("保存") { owner.write() }.buttonStyle(.borderless)
                .disabled(!owner.ready).accessibilityIdentifier("p1.web.write")
            Button("遅延保存") { owner.write(delayMilliseconds: 5_000) }.buttonStyle(.borderless)
                .disabled(!owner.ready).accessibilityIdentifier("p1.web.write-delayed")
            Button("保存失敗") { owner.write(failBeforeCommit: true) }.buttonStyle(.borderless)
                .disabled(!owner.ready).accessibilityIdentifier("p1.web.write-fail")
            Button("保存を取消") { owner.cancelWrite() }.buttonStyle(.borderless)
                .accessibilityIdentifier("p1.web.cancel-write")
            Button("読込") { owner.read() }.buttonStyle(.borderless)
                .disabled(!owner.ready).accessibilityIdentifier("p1.web.read")
            Section("Web認証") {
                Text(owner.authenticationResult).accessibilityIdentifier("p1.web.auth-result")
                Button("認証開始") { owner.startAuthentication(path: "complete") }.buttonStyle(.borderless)
                    .accessibilityIdentifier("p1.web.auth-start")
                Button("認証取消検証") { owner.startAuthentication(path: "hold") }.buttonStyle(.borderless)
                    .accessibilityIdentifier("p1.web.auth-hold")
                Button("認証取消") { owner.cancelAuthentication() }.buttonStyle(.borderless)
                    .accessibilityIdentifier("p1.web.auth-cancel")
            }
        }
        .navigationTitle(owner.id.rawValue)
    }
}

private struct WebPage: UIViewRepresentable {
    let owner: Owner
    func makeCoordinator() -> Coordinator { Coordinator(owner: owner) }
    func makeUIView(context: Context) -> WKWebView {
        owner.webView.navigationDelegate = context.coordinator
        owner.webView.loadHTMLString(Self.html, baseURL: URL(string: "https://jibunkit.example/ownership")!)
        return owner.webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let owner: Owner
        init(owner: Owner) { self.owner = owner }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { owner.ready = true }
    }

    static let html = """
    <!doctype html><meta charset="utf-8"><p>P1 Web</p><script>
    const dbName='p1-web', storeName='values', key='owner';
    function openDB(){return new Promise((ok,no)=>{const r=indexedDB.open(dbName,1);r.onupgradeneeded=()=>r.result.createObjectStore(storeName);r.onerror=()=>no(r.error);r.onsuccess=()=>ok(r.result)})}
    async function idbRead(){const all=await indexedDB.databases();if(!all.some(x=>x.name===dbName))return'missing';const db=await openDB();return new Promise((ok,no)=>{const tx=db.transaction(storeName);const r=tx.objectStore(storeName).get(key);tx.oncomplete=()=>{db.close();ok(r.result||'missing')};tx.onerror=()=>{db.close();no(tx.error)}})}
    window.p1Read=async()=>{const local=localStorage.getItem(key)||'missing';const row=document.cookie.split('; ').find(x=>x.startsWith(key+'='));const cookie=row?decodeURIComponent(row.substring(key.length+1)):'missing';return `local=${local} cookie=${cookie} indexeddb=${await idbRead()}`};
    window.p1Write=async(value,delay,fail)=>{if(delay)await new Promise(ok=>setTimeout(ok,delay));if(fail)throw new Error('requested failure before commit');localStorage.setItem(key,value);document.cookie=`${key}=${encodeURIComponent(value)}; Max-Age=86400; Path=/; SameSite=Lax`;const db=await openDB();await new Promise((ok,no)=>{const tx=db.transaction(storeName,'readwrite');tx.objectStore(storeName).put(value,key);tx.oncomplete=()=>{db.close();ok()};tx.onerror=()=>{db.close();no(tx.error)}});return await window.p1Read()};
    </script>
    """
}
#endif
