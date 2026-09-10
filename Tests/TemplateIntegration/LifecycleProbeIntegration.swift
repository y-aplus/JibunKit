// Included only in the isolated CI host, never in a distributed IPA.
import SwiftUI
import UIKit
import Observation
import JibunKitCore
import UserNotifications
import Security
import WebKit

@MainActor
@Observable
final class LifecycleProbeState {
    var events: [String] = []
    var restoredValue = "original"
    var showingRestore = false
    var idleLease: MiniAppIdleTimerLease?
    var taskStatus = "idle"
    var categories = "unread"
    var foregroundCount = 0
    var lastAction = "none"
    var scheduleStatus = "idle"
    var restoreFault: String { ProcessInfo.processInfo.environment["JIBUNKIT_RESTORE_FAULT"] ?? "" }

    func stopForRestore(owner: String) async throws {
        if owner == "lifecycle-a", restoreFault == "stop" { throw MiniAppBackupError.invalidEntry }
        await shutdown()
    }

    func resumeForRestore(owner: String) throws {
        if owner == "lifecycle-a", ["resume", "both"].contains(restoreFault) {
            throw MiniAppBackupError.invalidEntry
        }
        resumeAfterRestore()
    }

    func schedule(context: MiniAppContext, action: Bool = false) async {
        do {
            let center = UNUserNotificationCenter.current()
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                scheduleStatus = "denied"
                return
            }
            if action {
                let categories = await center.notificationCategories()
                guard let category = categories.first(where: { $0.identifier == context.notificationCategoryIdentifier(for: "initial") }),
                      category.actions.contains(where: { $0.identifier == "same-action" }) else {
                    scheduleStatus = "missing native action registration"
                    return
                }
            }
            let content = UNMutableNotificationContent()
            content.title = action ? "Action-" + context.id.rawValue : context.id.rawValue
            if action { content.body = "Choose Action to deliver to the owning Feature." }
            content.categoryIdentifier = action ? context.notificationCategoryIdentifier(for: "initial") : ""
            content.userInfo = context.notificationUserInfo
            try await center.add(UNNotificationRequest(
                identifier: context.notificationRequestIdentifier(for: action ? "action" : "foreground"), content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: action ? 10 : 2, repeats: false)))
            scheduleStatus = "scheduled"
        } catch { scheduleStatus = "error: \(error)" }
    }

    func readCategories() async {
        let values = await UNUserNotificationCenter.current().notificationCategories()
        categories = values.map(\.identifier).sorted().joined(separator: ",")
    }

    func replaceCategories(context: MiniAppContext, key: String?) async {
        do {
            let categories = key.map { [LifecycleProbeIntegration.category(context, key: $0)] } ?? []
            try context.replaceNotificationCategories(with: categories)
            await readCategories()
        } catch {
            categories = "error: \(error)"
        }
    }
    private var runtime = MiniAppRuntime()
    private var input: AsyncStream<Void>.Continuation?

    func start() {
        guard taskStatus != "running" else { return }
        let channel = AsyncStream<Void>.makeStream()
        input = channel.continuation
        taskStatus = "running"
        do {
            try runtime.start { [weak self] in
                for await _ in channel.stream { }
                await self?.finish(cancelled: Task.isCancelled)
            }
        } catch { taskStatus = "closed"; input = nil }
    }

    func cancel() { runtime.cancelTasks() }
    func acquireIdle(context: MiniAppContext) {
        guard idleLease == nil else { return }
        let lease = MiniAppIdleTimer.shared.preventSleep(for: context.id)
        do {
            try runtime.onShutdown { lease.release() }
            idleLease = lease
        } catch { lease.release() }
    }
    func resumeAfterRestore() {
        idleLease = nil
        runtime = MiniAppRuntime()
        taskStatus = "idle"
    }
    func applyRestored(_ value: String) throws {
        guard runtime.isClosed, taskStatus == "closed" else { throw MiniAppBackupError.invalidEntry }
        restoredValue = value
    }
    func shutdown() async {
        await runtime.shutdown()
        taskStatus = "closed"
    }
    func complete() { input?.finish() }
    private func finish(cancelled: Bool) {
        taskStatus = cancelled ? "cancelled" : "completed"
        input = nil
    }
    func receive(_ phase: MiniAppHostPhase) {
        switch phase {
        case .active: events.append("active")
        case .inactive: events.append("inactive")
        case .background: events.append("background")
        }
    }
}

@MainActor
enum LifecycleProbeIntegration {
    private static let first = LifecycleProbeState()
    private static let second = LifecycleProbeState()
    static let definitions = [definition("lifecycle-a", state: first), definition("lifecycle-b", state: second)]

    static func category(_ context: MiniAppContext, key: String) -> UNNotificationCategory {
        UNNotificationCategory(identifier: context.notificationCategoryIdentifier(for: key),
            actions: [UNNotificationAction(identifier: "same-action", title: "Action", options: [])],
            intentIdentifiers: [], options: [.customDismissAction])
    }

    private static func definition(_ id: String, state: LifecycleProbeState) -> MiniAppDefinition {
        let context = MiniAppContext(id: MiniAppID(id))
        let backup = MiniAppBackupProvider(id: context.id, export: {
            await MainActor.run { MiniAppBackupEntry(id: context.id, schemaVersion: 1, payload: Data(state.restoredValue.utf8)) }
        }, prepare: { entry in
            guard entry.schemaVersion == 1, let value = String(data: entry.payload, encoding: .utf8) else {
                throw MiniAppBackupError.invalidEntry
            }
            return MiniAppPreparedRestore {
                try await MainActor.run {
                    try state.applyRestored(value)
                    // Fail after mutation to exercise the partial-application warning.
                    if id == "lifecycle-a", ["apply", "both"].contains(state.restoreFault) {
                        throw MiniAppBackupError.invalidEntry
                    }
                }
            }
        })
        return MiniAppDefinition(id: context.id, title: id, systemImage: "clock",
                          backup: backup,
                          restoreLifecycle: MiniAppRestoreLifecycle(stop: { try await state.stopForRestore(owner: id) },
                              resume: { try await state.resumeForRestore(owner: id) }),
                          onHostPhaseChange: { state.receive($0) },
                          onNotificationAction: { action in
                              if case let .custom(identifier) = action.kind { state.lastAction = identifier }
                          },
                          notificationCategories: [category(context, key: "initial")],
                          notificationPresentation: { event in
                              // Action delivery must survive slow test navigation into background.
                              if event.categoryIdentifier == context.notificationCategoryIdentifier(for: "initial") {
                                  return [.list]
                              }
                              state.foregroundCount += 1
                              return id == "lifecycle-a" ? [] : [.list]
                          }) { _ in
            VStack {
                Button("Restore probe") { state.showingRestore = true }
                    .accessibilityIdentifier("runtime.restore.open")
                Text(state.restoredValue).accessibilityIdentifier("runtime.restored.value")
                NavigationLink("Idle timer") { IdleTimerProbeView(context: context, state: state) }
                    .accessibilityIdentifier("idle.open")
                NavigationLink("Web data") { WebDataProbeView(context: context) }
                    .accessibilityIdentifier("webdata.open")
                NavigationLink("Keychain") { KeychainProbeView(context: context) }
                    .accessibilityIdentifier("keychain.open")
                Text(state.events.joined(separator: ","))
                    .accessibilityIdentifier("lifecycle.events")
                Text(state.categories).accessibilityIdentifier("notification.categories")
                Button("Read categories") { Task { await state.readCategories() } }
                    .accessibilityIdentifier("notification.read")
                Button("Replace categories") { Task { await state.replaceCategories(context: context, key: "updated") } }
                    .accessibilityIdentifier("notification.replace")
                Button("Remove categories") { Task { await state.replaceCategories(context: context, key: nil) } }
                    .accessibilityIdentifier("notification.remove")
                Text("\(state.foregroundCount)").accessibilityIdentifier("notification.foreground.count")
                Text(state.scheduleStatus).accessibilityIdentifier("notification.schedule.status")
                Button("Schedule notification") { Task { await state.schedule(context: context) } }
                    .accessibilityIdentifier("notification.schedule")
                Button("Clear notifications") {
                    Task {
                        await context.removeAllOwnedNotifications()
                        state.scheduleStatus = "cleared"
                    }
                }.accessibilityIdentifier("notification.clear")
                Text(state.lastAction).accessibilityIdentifier("notification.action.result")
                Button("Schedule action") { Task { await state.schedule(context: context, action: true) } }
                    .accessibilityIdentifier("notification.action.schedule")
                Text(state.taskStatus).accessibilityIdentifier("lifecycle.task.status")
                Button("Start", action: state.start).accessibilityIdentifier("lifecycle.task.start")
                Button("Cancel", action: state.cancel).accessibilityIdentifier("lifecycle.task.cancel")
                Button("Complete", action: state.complete).accessibilityIdentifier("lifecycle.task.complete")
            }
            .sheet(isPresented: Binding(get: { state.showingRestore }, set: { state.showingRestore = $0 })) {
                BackupScreen(definitions: definitions, importedBackup: try! MiniAppBackup(entries: [
                    MiniAppBackupEntry(id: context.id, schemaVersion: 1, payload: Data("restored".utf8))
                ]))
            }
        }
    }
}


// Uses only synthetic test credentials. This view is never distributed.
private struct KeychainProbeView: View {
    let context: MiniAppContext
    @State private var result = "unread"
    private var store: MiniAppKeychain { MiniAppKeychain(context: context, service: "ci-login") }

    var body: some View {
        VStack {
            Text(result).accessibilityIdentifier("keychain.result")
            Button("Save") {
                perform {
                    let data = Data(context.id.rawValue.utf8)
                    try store.set(data, for: "same-account", accessibility: kSecAttrAccessibleWhenUnlocked)
                    guard try protection() == kSecAttrAccessibleWhenUnlocked as String else { return "wrong initial protection" }
                    try store.set(data, for: "same-account", accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
                    // An ordinary data update must not reset the explicitly selected protection.
                    try store.set(data, for: "same-account")
                    guard try protection() == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String else { return "wrong updated protection" }
                    return "saved"
                }
            }.accessibilityIdentifier("keychain.save")
            Button("Read") {
                perform {
                    guard let data = try store.data(for: "same-account") else { return "missing" }
                    return String(decoding: data, as: UTF8.self)
                }
            }.accessibilityIdentifier("keychain.read")
            Button("Logout") {
                perform { try store.removeAll(); return "removed" }
            }.accessibilityIdentifier("keychain.remove")
        }
    }

    private func protection() throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.serviceIdentifier, kSecAttrAccount as String: "same-account",
            kSecAttrSynchronizable as String: false, kSecReturnAttributes as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return "OSStatus: \(status)" }
        return (result as? [String: Any])?[kSecAttrAccessible as String] as? String
    }

    private func perform(_ operation: () throws -> String) {
        do { result = try operation() }
        catch { result = "error: \(error)" }
    }
}


private struct WebDataProbeView: View {
    let context: MiniAppContext
    @State private var result = "unread"
    @State private var webView: WKWebView
    @State private var pageReady = false
    @State private var baselineReady = false
    @State private var baselineView: WKWebView
    @State private var diagnostic = "not-read"

    init(context: MiniAppContext) {
        self.context = context
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = context.websiteDataStore()
        let view = WKWebView(frame: .zero, configuration: configuration)
        _webView = State(initialValue: view)
        _baselineView = State(initialValue: WKWebView(frame: .zero, configuration: WKWebViewConfiguration()))
    }

    var body: some View {
        VStack {
            WebDataProbeWebView(webView: webView, ready: $pageReady).frame(height: 80)
            WebDataProbeWebView(webView: baselineView, ready: $baselineReady).frame(height: 40)
            NavigationLink("Persistent HTTP cookies") { NetworkCookieProbeView(context: context) }
                .accessibilityIdentifier("network.cookies.open")
            NavigationLink("Persistent HTTP passwords") { NetworkPasswordProbeView(context: context) }
                .accessibilityIdentifier("network.passwords.open")
            NavigationLink("Scene navigation") { SceneNavigationProbeView() }
                .accessibilityIdentifier("scene.navigation.open")
            Text(diagnostic).accessibilityIdentifier("webdata.diagnostic")
            Text(pageReady && baselineReady ? "page-ready" : "page-loading").accessibilityIdentifier("webdata.page")
            Text(result).accessibilityIdentifier("webdata.result")
            Button("Save cookie") {
                Task {
                    let cookie = HTTPCookie(properties: [.domain: "jibunkit.example", .path: "/",
                        .name: "account", .value: context.id.rawValue,
                        .expires: Date().addingTimeInterval(86400)])!
                    await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                    var baselineProperties = cookie.properties!
                    baselineProperties[.name] = "baseline-" + context.id.rawValue
                    let baselineCookie = HTTPCookie(properties: baselineProperties)!
                    await baselineView.configuration.websiteDataStore.httpCookieStore.setCookie(baselineCookie)
                    diagnostic = "saved profile=\(webView.configuration.websiteDataStore.identifier?.uuidString ?? "nil") persistent=\(webView.configuration.websiteDataStore.isPersistent) sessionOnly=\(cookie.isSessionOnly) expires=\(cookie.expiresDate?.description ?? "nil")"
                    result = "saved"
                }
            }.accessibilityIdentifier("webdata.save")
            Button("Read cookie") {
                Task {
                    let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                    let baseline = await baselineView.configuration.websiteDataStore.httpCookieStore.allCookies()
                    let baselineValue = baseline.first { $0.name == "baseline-" + context.id.rawValue }?.value ?? "missing"
                    let stored = cookies.first { $0.name == "account" && $0.domain == "jibunkit.example" }
                    result = stored?.value ?? "missing"
                    diagnostic = "owner=\(context.id.rawValue) profile=\(result) default=\(baselineValue) profileCookieCount=\(cookies.count) sessionOnly=\(stored?.isSessionOnly.description ?? "nil")"
                    print("WEB-PERSISTENCE \(diagnostic)")
                }
            }.accessibilityIdentifier("webdata.read")
            Button("Clear web data") {
                Task {
                    await webView.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                    result = "removed"
                }
            }.accessibilityIdentifier("webdata.remove")
        }
    }
}


private struct WebDataProbeWebView: UIViewRepresentable {
    let webView: WKWebView
    @Binding var ready: Bool
    func makeCoordinator() -> Coordinator { Coordinator(ready: $ready) }
    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString("<p>Persistent Web data probe</p>", baseURL: URL(string: "https://jibunkit.example"))
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var ready: Bool
        init(ready: Binding<Bool>) { _ready = ready }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true }
    }
}


private struct SceneNavigationProbeView: View {
    @State private var first = AppNavigation()
    @State private var second = AppNavigation()
    @State private var router = MiniAppSceneRouter()
    @State private var registrations: [UUID] = []

    var body: some View {
        VStack {
            Text("A=\(first.path.count) B=\(second.path.count)")
                .accessibilityIdentifier("scene.navigation.result")
            Button("Open A") { first.open(.counter) }.accessibilityIdentifier("scene.navigation.a.open")
            Button("Push A") { first.path.append("detail-a") }.accessibilityIdentifier("scene.navigation.a.push")
            Button("Open B") { second.open(.counter) }.accessibilityIdentifier("scene.navigation.b.open")
            Button("Push B") { second.path.append("detail-b") }.accessibilityIdentifier("scene.navigation.b.push")
            Button("Notification to list") { router.open(nil) }.accessibilityIdentifier("scene.navigation.route")
            Button("Activate A") {
                guard registrations.count == 2 else { return }
                router.update(registrations[0], isActive: true)
            }.accessibilityIdentifier("scene.navigation.activate-a")
            Button("Remove A") {
                guard let id = registrations.first else { return }
                router.unregister(id)
            }.accessibilityIdentifier("scene.navigation.remove-a")
        }
        .onAppear {
            guard registrations.isEmpty else { return }
            registrations = [
                router.register(isActive: false) { [weak first] in first?.openNotificationRoute($0) },
                router.register(isActive: true) { [weak second] in second?.openNotificationRoute($0) }
            ]
        }
        .onDisappear {
            for id in registrations { router.unregister(id) }
            registrations = []
        }
    }
}

private struct NetworkPasswordProbeView: View {
    let context: MiniAppContext
    @State private var store: MiniAppPasswordCredentialStore?
    @State private var result = "loading"
    private let space = URLProtectionSpace(host: "jibunkit.example", port: 443,
        protocol: "https", realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)

    var body: some View {
        VStack {
            Text(result).accessibilityIdentifier("network.passwords.result")
            Button("Save password") {
                do {
                    guard let store else { throw MiniAppPasswordCredentialStore.Failure.invalidArchive }
                    store.storage.setDefaultCredential(URLCredential(user: "account",
                        password: context.id.rawValue, persistence: .forSession), for: space)
                    try store.save()
                    result = "saved"
                } catch { result = "error: \(error)" }
            }.accessibilityIdentifier("network.passwords.save")
            Button("Read password") {
                // This CI-only fixture uses owner IDs, never real passwords.
                result = store?.storage.defaultCredential(for: space)?.password ?? "missing"
            }.accessibilityIdentifier("network.passwords.read")
            Button("Log out") {
                do {
                    guard let store else { throw MiniAppPasswordCredentialStore.Failure.invalidArchive }
                    try store.clear()
                    result = "cleared"
                } catch { result = "error: \(error)" }
            }.accessibilityIdentifier("network.passwords.clear")
        }
        .task {
            do {
                store = try MiniAppPasswordCredentialStore(context: context, profile: "ci-persistent-password")
                result = "ready"
            } catch { result = "error: \(error)" }
        }
    }
}

private struct NetworkCookieProbeView: View {
    let context: MiniAppContext
    @State private var store: MiniAppCookieStore?
    @State private var result = "loading"

    var body: some View {
        VStack {
            Text(result).accessibilityIdentifier("network.cookies.result")
            Button("Save login") {
                do {
                    guard let store else { throw MiniAppCookieStore.Failure.invalidArchive }
                    let url = URL(string: "https://jibunkit.example/account")!
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: [
                        "Set-Cookie": "account=\(context.id.rawValue); Path=/; Max-Age=86400; Secure; HttpOnly"
                    ], for: url)
                    guard cookies.count == 1 else { throw MiniAppCookieStore.Failure.unsupportedCookie }
                    store.storage.setCookie(cookies[0])
                    try store.save()
                    result = "saved"
                } catch { result = "error: \(error)" }
            }.accessibilityIdentifier("network.cookies.save")
            Button("Read login") {
                guard let cookie = store?.storage.cookies?.first(where: { $0.name == "account" }) else {
                    result = "missing"
                    return
                }
                result = "\(cookie.value)|secure=\(cookie.isSecure)|httpOnly=\(cookie.isHTTPOnly)"
            }.accessibilityIdentifier("network.cookies.read")
            Button("Log out") {
                do {
                    guard let store else { throw MiniAppCookieStore.Failure.invalidArchive }
                    try store.clear()
                    result = "cleared"
                } catch { result = "error: \(error)" }
            }.accessibilityIdentifier("network.cookies.clear")
        }
        .task {
            do {
                store = try MiniAppCookieStore(context: context, profile: "ci-persistent-login")
                result = "ready"
            } catch { result = "error: \(error)" }
        }
    }
}

private struct IdleTimerProbeView: View {
    let context: MiniAppContext
    let state: LifecycleProbeState
    @State private var result = "unread"
    var body: some View {
        VStack {
            Text(result).accessibilityIdentifier("idle.result")
            Button("Acquire") {
                if state.idleLease == nil {
                    state.acquireIdle(context: context)
                }
                read()
            }.accessibilityIdentifier("idle.acquire")
            Button("Release") {
                state.idleLease?.release()
                state.idleLease = nil
                read()
            }.accessibilityIdentifier("idle.release")
            Button("Read", action: read).accessibilityIdentifier("idle.read")
            Button("Shutdown") { Task { await state.shutdown(); read() } }
                .accessibilityIdentifier("idle.shutdown")
        }
        .navigationTitle("Idle timer")
    }
    private func read() {
        result = UIApplication.shared.isIdleTimerDisabled ? "disabled" : "enabled"
    }
}
