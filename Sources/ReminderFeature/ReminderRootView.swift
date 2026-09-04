#if os(iOS)
import JibunKitCore
import SwiftUI

public struct ReminderRootView: View {
    private let store: ReminderStore
    private let scheduler: ReminderNotificationScheduler

    @State private var message = ""
    @State private var statusMessage: String?
    @State private var isError = false

    public init(context: MiniAppContext) {
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
                    Task {
                        await save()
                    }
                }

                Button("10秒後に通知") {
                    Task {
                        await scheduleNotification()
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
