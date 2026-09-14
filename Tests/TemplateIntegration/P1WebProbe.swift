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
    var pageStatus = "page-loading"
    var result = "idle"
    var authenticationResult = "idle"
    private var operationTask: Task<Void, Never>?
    private var operationID: UUID?
    private let precommitHold = PrecommitHold()
    private var needsReload = true
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
            self?.operationTask = nil
            self?.operationID = nil
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

    var isOperating: Bool { operationTask != nil }

    func write(heldBeforeCommit: Bool = false, failBeforeCommit: Bool = false) {
        guard let runtime = lifetime.runtime else { result = "failed: not running"; return }
        guard operationTask == nil else { result = "busy"; return }
        let token = UUID()
        operationID = token
        result = "writing"
        do {
            operationTask = try runtime.start { [weak self] in
                guard let self else { return }
                do {
                    let value = try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: self.id) {
                        if heldBeforeCommit {
                            await self.markWriteWaiting(token: token)
                            try await self.precommitHold.wait()
                        }
                        try Task.checkCancellation()
                        return try await self.evaluateWrite(failBeforeCommit: failBeforeCommit)
                    }
                    await self.finishOperation(token: token, result: value)
                } catch is CancellationError {
                    await self.finishOperation(token: token, result: "cancelled")
                } catch {
                    await self.finishOperation(token: token, result: "failed: \(error)")
                }
            }
        } catch { operationID = nil; result = "failed: closed" }
    }

    func read() {
        guard let runtime = lifetime.runtime else { result = "failed: not running"; return }
        guard operationTask == nil else { result = "busy"; return }
        let token = UUID()
        operationID = token
        result = "reading"
        do {
            operationTask = try runtime.start { [weak self] in
                guard let self else { return }
                do {
                    let value = try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: self.id) {
                        try await self.evaluateRead()
                    }
                    await self.finishOperation(token: token, result: value)
                } catch is CancellationError {
                    await self.finishOperation(token: token, result: "cancelled read")
                } catch { await self.finishOperation(token: token, result: "failed: \(error)") }
            }
        } catch { operationID = nil; result = "failed: closed" }
    }

    func releaseWrite() { precommitHold.release() }
    func cancelOperation() { operationTask?.cancel() }

    func removeData() async {
        await dataStore.removeData(
            ofTypes: [WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage,
                      WKWebsiteDataTypeIndexedDBDatabases],
            modifiedSince: .distantPast
        )
        ready = false
        pageStatus = "page-loading"
        needsReload = true
    }

    func startAuthentication(path: String) {
        guard let authentication else { authenticationResult = "failed: not running"; return }
        guard authenticationRequest == nil else { authenticationResult = "busy: own request"; return }
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
        guard let string = value as? String else { throw ProbeFailure.nonStringResult }
        return string
    }

    private func evaluateWrite(failBeforeCommit: Bool) async throws -> String {
        try Task.checkCancellation()
        let value = try await webView.callAsyncJavaScript(
            "return await window.p1Write(value, fail)",
            arguments: ["value": id.rawValue, "fail": failBeforeCommit], contentWorld: .page)
        guard let string = value as? String else { throw ProbeFailure.nonStringResult }
        return string
    }

    private func markWriteWaiting(token: UUID) {
        guard operationID == token else { return }
        result = "write waiting"
    }

    private func finishOperation(token: UUID, result: String) {
        guard operationID == token else { return }
        self.result = result
        operationID = nil
        operationTask = nil
    }

    func preparePage(coordinator: WKNavigationDelegate) {
        webView.navigationDelegate = coordinator
        guard needsReload, operationTask == nil else { return }
        needsReload = false
        ready = false
        pageStatus = "page-loading"
        webView.loadHTMLString(WebPage.html, baseURL: URL(string: "https://jibunkit.example/ownership")!)
    }

    func navigationStarted() { ready = false; pageStatus = "page-loading" }
    func navigationFinished() { ready = true; pageStatus = "page-ready" }
    func navigationFailed(_ error: Error) {
        ready = false
        needsReload = true
        pageStatus = "page-failed"
        if operationTask == nil { result = "failed: navigation \(error)" }
    }

    private enum ProbeFailure: Error { case nonStringResult }
}

@MainActor
private final class PrecommitHold {
    private var continuation: CheckedContinuation<Void, Error>?
    private var cancellationRequested = false
    private var waiting = false

    func wait() async throws {
        try Task.checkCancellation()
        waiting = true
        defer {
            waiting = false
            cancellationRequested = false
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if cancellationRequested {
                    cancellationRequested = false
                    continuation.resume(throwing: CancellationError())
                } else {
                    self.continuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
        cancellationRequested = false
    }

    func cancel() {
        if let continuation {
            self.continuation = nil
            continuation.resume(throwing: CancellationError())
        } else if waiting {
            cancellationRequested = true
        }
    }
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
            Text(owner.pageStatus).accessibilityIdentifier("p1.web.page")
            Text(owner.result).accessibilityIdentifier("p1.web.result")
            Button("保存") { owner.write() }.buttonStyle(.borderless)
                .disabled(!owner.ready || owner.isOperating).accessibilityIdentifier("p1.web.write")
            Button("保存前で保留") { owner.write(heldBeforeCommit: true) }.buttonStyle(.borderless)
                .disabled(!owner.ready || owner.isOperating).accessibilityIdentifier("p1.web.write-delayed")
            Button("保留を解除") { owner.releaseWrite() }.buttonStyle(.borderless)
                .disabled(!owner.isOperating).accessibilityIdentifier("p1.web.release-write")
            Button("保存失敗") { owner.write(failBeforeCommit: true) }.buttonStyle(.borderless)
                .disabled(!owner.ready || owner.isOperating).accessibilityIdentifier("p1.web.write-fail")
            Button("処理を取消") { owner.cancelOperation() }.buttonStyle(.borderless)
                .disabled(!owner.isOperating)
                .accessibilityIdentifier("p1.web.cancel-write")
            Button("読込") { owner.read() }.buttonStyle(.borderless)
                .disabled(!owner.ready || owner.isOperating).accessibilityIdentifier("p1.web.read")
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
        owner.preparePage(coordinator: context.coordinator)
        return owner.webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let owner: Owner
        init(owner: Owner) { self.owner = owner }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            owner.navigationStarted()
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.readyState === 'complete' && typeof window.p1Read === 'function' && typeof window.p1Write === 'function'") { value, error in
                if let error { self.owner.navigationFailed(error) }
                else if value as? Bool == true { self.owner.navigationFinished() }
                else { self.owner.navigationFailed(ProbeNavigationFailure.functionsUnavailable) }
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            owner.navigationFailed(error)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            owner.navigationFailed(error)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            owner.navigationFailed(ProbeNavigationFailure.webContentTerminated)
        }
    }

    private enum ProbeNavigationFailure: Error { case functionsUnavailable, webContentTerminated }

    static let html = """
    <!doctype html><meta charset="utf-8"><p>P1 Web</p><script>
    const dbName='p1-web', storeName='values', key='owner';
    function openDB(){return new Promise((ok,no)=>{const r=indexedDB.open(dbName,1);r.onupgradeneeded=()=>r.result.createObjectStore(storeName);r.onerror=()=>no(r.error);r.onsuccess=()=>ok(r.result)})}
    async function idbRead(){const all=await indexedDB.databases();if(!all.some(x=>x.name===dbName))return'missing';const db=await openDB();return new Promise((ok,no)=>{let done=false;const finish=(error,value)=>{if(done)return;done=true;db.close();error?no(error):ok(value)};try{const tx=db.transaction(storeName,'readonly');const r=tx.objectStore(storeName).get(key);tx.oncomplete=()=>finish(null,r.result||'missing');tx.onerror=()=>finish(tx.error||new Error('IndexedDB read failed'));tx.onabort=()=>finish(tx.error||new Error('IndexedDB read aborted'))}catch(error){finish(error)}})}
    window.p1Read=async()=>{const local=localStorage.getItem(key)||'missing';const row=document.cookie.split('; ').find(x=>x.startsWith(key+'='));const cookie=row?decodeURIComponent(row.substring(key.length+1)):'missing';return `local=${local} cookie=${cookie} indexeddb=${await idbRead()}`};
    window.p1Write=async(value,fail)=>{if(fail)throw new Error('requested failure before commit');localStorage.setItem(key,value);document.cookie=`${key}=${encodeURIComponent(value)}; Max-Age=86400; Path=/; SameSite=Lax`;const db=await openDB();await new Promise((ok,no)=>{let done=false;const tx=db.transaction(storeName,'readwrite');const finish=(error)=>{if(done)return;done=true;db.close();error?no(error):ok()};tx.objectStore(storeName).put(value,key);tx.onerror=()=>finish(tx.error||new Error('IndexedDB write failed'));tx.onabort=()=>finish(tx.error||new Error('IndexedDB write aborted'));tx.oncomplete=()=>finish()});return await window.p1Read()};
    </script>
    """
}
#endif
