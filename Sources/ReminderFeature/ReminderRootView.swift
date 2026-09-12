#if os(iOS)
import JibunKitCore
import SwiftUI

public struct ReminderRootView: View {
    private let store: ReminderStore
    private let scheduler: ReminderNotificationScheduler
    private let owner: MiniAppID
    @Environment(\.miniAppConsentStore) private var consents
    @Environment(\.miniAppLifetime) private var lifetime

    @State private var message = ""
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var requestingConsent = false

    public init(context: MiniAppContext) {
        owner = context.id
        store = ReminderStore(context: context)
        scheduler = ReminderNotificationScheduler(context: context)
    }

    public var body: some View {
        Form {
            Section("通知内容") {
                TextField("例: 水を飲む", text: $message)
            }

            Section {
                Button("保存") {
                    runOwned { await save() }
                }

                Button("10秒後に通知") {
                    switch consents?.consent(for: owner, permissionID: ReminderNotificationScheduler.permission.id) {
                    case .notDetermined?: requestingConsent = true
                    case .denied?:
                        statusMessage = "リマインダーでの通知利用を拒否しています。ミニアプリの管理で変更できます。"
                        isError = true
                    default: runOwned { await scheduleNotification() }
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(isError ? .red : .secondary)
                }
            }
        }
        .navigationTitle("リマインダー")
        .task {
            await load()
        }
        .alert("リマインダーが通知を利用します", isPresented: $requestingConsent) {
            Button("許可") {
                consents?.setConsent(.allowed, for: owner, permissionID: ReminderNotificationScheduler.permission.id)
                runOwned { await scheduleNotification() }
            }
            Button("拒否", role: .cancel) {
                consents?.setConsent(.denied, for: owner, permissionID: ReminderNotificationScheduler.permission.id)
            }
        } message: {
            Text(ReminderNotificationScheduler.permission.purpose + "\n拒否した場合: " + ReminderNotificationScheduler.permission.deniedBehavior)
        }
    }

    @MainActor
    private func runOwned(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        if let lifetime {
            guard lifetime.isStartAllowed, let runtime = lifetime.runtime else { return }
            do { try runtime.start { await operation() } }
            catch { statusMessage = "このアプリは終了しています"; isError = true }
        } else {
            Task { @MainActor in await operation() }
        }
    }

    @MainActor
    private func load() async {
        do {
            message = try await store.currentMessage()
            statusMessage = nil
            isError = false
        } catch {
            statusMessage = "保存内容を読み込めません"
            isError = true
        }
    }

    @MainActor
    private func save() async {
        do {
            _ = try await saveCurrentMessage()
            statusMessage = "保存しました"
            isError = false
        } catch ReminderInputError.emptyMessage {
            statusMessage = "通知内容を入力してください"
            isError = true
        } catch {
            statusMessage = "保存できません"
            isError = true
        }
    }

    @MainActor
    private func scheduleNotification() async {
        do {
            let savedMessage = try await saveCurrentMessage()
            let result = try await scheduler.schedule(
                message: savedMessage
            )
            switch result {
            case .scheduled:
                statusMessage = "10秒後の通知を予約しました"
                isError = false
            case .denied:
                statusMessage = "通知は許可されていません。設定で変更できます"
                isError = true
            }
        } catch ReminderInputError.emptyMessage {
            statusMessage = "通知内容を入力してください"
            isError = true
        } catch {
            statusMessage = "通知を予約できません"
            isError = true
        }
    }

    @MainActor
    private func saveCurrentMessage() async throws -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw ReminderInputError.emptyMessage
        }
        message = try await store.saveMessage(trimmedMessage)
        return message
    }
}

private enum ReminderInputError: Error {
    case emptyMessage
}
#endif
