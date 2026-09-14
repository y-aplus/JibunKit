// Diagnostic host only: normal Definition, delegate and management entry points.
#if os(iOS)
import JibunKitCore
import Observation
import SwiftUI
import UIKit
import UserNotifications

@MainActor
enum P1NotificationsProbe {
    private static let a = NotificationOwner("p1-notification-a", silent: true)
    private static let b = NotificationOwner("p1-notification-b", silent: false)
    static let ownerADefinition = definition(a, title: "通知検証 A")
    static let ownerBDefinition = definition(b, title: "通知検証 B")

    private static func definition(_ owner: NotificationOwner, title: String) -> MiniAppDefinition {
        MiniAppDefinition(
            id: owner.id, title: title, systemImage: "bell.badge",
            lifetime: owner.lifetime,
            removal: .init(id: owner.id, dataDescription: "通知検証の画像原本と操作記録") {
                try owner.removeData()
            },
            onUnregister: { try owner.attachments.removeStagingFiles() },
            onNotificationAction: { await owner.receive($0) },
            notificationCategories: [owner.category],
            notificationPresentation: { owner.present($0) }
        ) { _ in NotificationProbeView(owner: owner) }
    }
}

@MainActor
@Observable
private final class NotificationOwner {
    enum Mode: Equatable, Sendable { case pending, deliver, held, fail }
    enum Failure: Error { case requestedFailure, missingCopy, noImage }
    nonisolated let id: MiniAppID
    let silent: Bool
    let lifetime: MiniAppFeatureLifetime
    var result = "idle"
    var inventory = "unread"
    var action = "none"
    var foreground = "none"
    var busy = false
    private var task: Task<Void, Never>?
    private let center = UNUserNotificationCenter.current()
    private var context: MiniAppContext { .init(id: id) }
    private var originalDirectory: URL {
        URL.documentsDirectory.appendingPathComponent("P1Notifications", isDirectory: true)
            .appendingPathComponent(id.storageNamespace, isDirectory: true)
    }
    private var original: URL { originalDirectory.appendingPathComponent("original.png") }
    var attachments: MiniAppNotificationAttachments {
        get throws {
            try .init(context: context, containerURL: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
        }
    }
    var category: UNNotificationCategory {
        .init(identifier: context.notificationCategoryIdentifier(for: "same-category"), actions: [
            UNNotificationAction(identifier: "mark", title: "記録", options: [.foreground]),
            UNTextInputNotificationAction(identifier: "reply", title: "返信", options: [.foreground],
                                          textInputButtonTitle: "送信", textInputPlaceholder: "検証文字列")
        ], intentIdentifiers: [], options: [.customDismissAction])
    }

    init(_ rawID: String, silent: Bool) {
        id = MiniAppID(rawID)
        self.silent = silent
        lifetime = .init(id: id)
    }

    func requestPermission() {
        run {
            let allowed = try await self.center.requestAuthorization(options: [.alert, .sound, .badge])
            return allowed ? "authorized" : "denied"
        }
    }

    func schedule(_ mode: Mode) {
        run {
            try self.prepareOriginal()
            return try await self.attachments.withFiles(copiedFrom: [self.original]) { files in
                guard let copy = files.first else { throw Failure.missingCopy }
                if mode == .held {
                    // No timed race with navigation: cancellation is the only release.
                    self.result = "prepared waiting"
                    try await NotificationCancellationGate().wait()
                }
                let attachment = try UNNotificationAttachment(identifier: "image", url: copy, options: nil)
                if mode == .fail { throw Failure.requestedFailure }
                let content = UNMutableNotificationContent()
                content.title = self.id.rawValue
                content.body = "長押しして「記録」または「返信」を確認"
                content.sound = .default
                content.categoryIdentifier = self.category.identifier
                content.userInfo = self.context.notificationUserInfo
                content.attachments = [attachment]
                let key = mode == .deliver ? "delivery" : "same-local-id"
                let request = UNNotificationRequest(identifier: self.context.notificationRequestIdentifier(for: key),
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: mode == .deliver ? 5 : 3600, repeats: false))
                try Task.checkCancellation()
                try await self.center.add(request)
                // Native acceptance is a commit, even if cancellation arrived during add.
                return mode == .deliver ? "registered delivery" : "registered pending"
            }
        }
    }

    func cancelPreparation() { task?.cancel() }

    func clearRequests() {
        run {
            await self.context.removeAllOwnedNotifications()
            return "requests cleared"
        }
    }

    func clearEvents() {
        run {
            for key in ["action", "foreground"] {
                UserDefaults.standard.removeObject(forKey: self.context.storageKey(key))
            }
            self.action = "none"
            self.foreground = "none"
            return "events cleared"
        }
    }

    func refresh() {
        run {
            let pending = await self.center.pendingNotificationRequests()
                .filter { self.context.ownsNotificationRequestIdentifier($0.identifier) }
            let delivered = await self.center.deliveredNotifications()
                .filter { self.context.ownsNotificationRequestIdentifier($0.request.identifier) }
            var readable = 0
            var matching = 0
            for request in pending {
                for attachment in request.content.attachments {
                    let scoped = attachment.url.startAccessingSecurityScopedResource()
                    defer { if scoped { attachment.url.stopAccessingSecurityScopedResource() } }
                    let bytes = try Data(contentsOf: attachment.url)
                    if !bytes.isEmpty { readable += 1 }
                    if FileManager.default.fileExists(atPath: self.original.path),
                       bytes == (try Data(contentsOf: self.original)) { matching += 1 }
                }
            }
            let staging = try self.attachments.directoryURL
            let copies = FileManager.default.fileExists(atPath: staging.path)
                ? try FileManager.default.contentsOfDirectory(atPath: staging.path).count : 0
            let hasOriginal = FileManager.default.fileExists(atPath: self.original.path)
            self.inventory = "pending=\(pending.count) readable=\(readable) matching=\(matching) delivered=\(delivered.count) original=\(hasOriginal) staging=\(copies)"
            self.action = UserDefaults.standard.string(forKey: self.context.storageKey("action")) ?? "none"
            self.foreground = UserDefaults.standard.string(forKey: self.context.storageKey("foreground")) ?? "none"
            return "read"
        }
    }

    func receive(_ event: MiniAppNotificationAction) async {
        do {
            try await lifetime.start()
            guard let runtime = lifetime.runtime else { throw MiniAppRuntime.Failure.closed }
            let work = try runtime.start { [self] in
                do {
                    try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: id) {
                        await self.record(event)
                    }
                } catch { await self.setResult("action failed: \(error)") }
            }
            await work.value
        } catch { result = "action failed: \(error)" }
    }

    private func record(_ event: MiniAppNotificationAction) {
        guard context.ownsNotificationRequestIdentifier(event.requestIdentifier) else {
            result = "action failed: foreign request"; return
        }
        let kind: String
        switch event.kind {
        case .open: kind = "open"
        case .dismiss: kind = "dismiss"
        case .custom(let name): kind = name
        }
        action = "\(id.rawValue) action=\(kind) text=\(event.userText ?? "none")"
        UserDefaults.standard.set(action, forKey: context.storageKey("action"))
    }

    func present(_ event: MiniAppForegroundNotification) -> UNNotificationPresentationOptions {
        foreground = "\(id.rawValue) policy=\(silent ? "silent" : "banner") request=\(event.requestIdentifier)"
        UserDefaults.standard.set(foreground, forKey: context.storageKey("foreground"))
        return silent ? [] : [.banner, .list, .sound]
    }

    // Called only under management's exclusive reservation after lifetime drain.
    func removeData() throws {
        try attachments.removeStagingFiles()
        if FileManager.default.fileExists(atPath: originalDirectory.path) {
            try FileManager.default.removeItem(at: originalDirectory)
        }
        for key in ["action", "foreground"] { UserDefaults.standard.removeObject(forKey: context.storageKey(key)) }
        action = "none"
        foreground = "none"
    }

    private func prepareOriginal() throws {
        guard !FileManager.default.fileExists(atPath: original.path) else { return }
        try FileManager.default.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { renderer in
            (silent ? UIColor.systemRed : UIColor.systemBlue).setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }
        guard let data = image.pngData() else { throw Failure.noImage }
        try data.write(to: original, options: .atomic)
    }

    private func run(_ operation: @escaping @MainActor @Sendable () async throws -> String) {
        guard !busy else { return }
        guard let runtime = lifetime.runtime else { result = "failed: not running"; return }
        busy = true
        result = "working"
        do {
            task = try runtime.start { [self] in
                do {
                    let value = try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: id) {
                        try await operation()
                    }
                    await finish(value)
                } catch is CancellationError { await finish("cancelled") }
                catch { await finish("failed: \(error)") }
            }
        } catch { busy = false; result = "failed: \(error)" }
    }

    private func finish(_ value: String) { result = value; busy = false; task = nil }
    private func setResult(_ value: String) { result = value }
}

@MainActor
private final class NotificationCancellationGate {
    private var continuation: CheckedContinuation<Void, Error>?
    func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { self.continuation = continuation }
            }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    private func cancel() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private struct NotificationProbeView: View {
    let owner: NotificationOwner
    var body: some View {
        List {
            Section("状態") {
                Text(owner.result).accessibilityIdentifier("p1.notification.result")
                Text(owner.inventory).accessibilityIdentifier("p1.notification.inventory")
                Text(owner.foreground).accessibilityIdentifier("p1.notification.foreground")
                Text(owner.action).accessibilityIdentifier("p1.notification.action")
            }
            Section("登録と確認") {
                operation("通知を許可", "authorize") { owner.requestPermission() }
                operation("1時間後の予約", "pending") { owner.schedule(.pending) }
                operation("5秒後に配信", "deliver") { owner.schedule(.deliver) }
                operation("準備後に停止して待つ", "held") { owner.schedule(.held) }
                operation("登録前の失敗", "fail") { owner.schedule(.fail) }
                Button("準備を取消") { owner.cancelPreparation() }
                    .buttonStyle(.borderless).accessibilityIdentifier("p1.notification.cancel")
                operation("この所有者の通知を解除", "clear") { owner.clearRequests() }
                operation("この所有者の検証記録を消去", "clear-events") { owner.clearEvents() }
                operation("実データを再読込", "read") { owner.refresh() }
            }
        }
        .navigationTitle(owner.id.rawValue)
    }
    private func operation(_ title: String, _ id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.borderless).disabled(owner.busy)
            .accessibilityIdentifier("p1.notification." + id)
    }
}
#endif
