#if os(iOS)
import JibunKitCore
import SwiftUI

public struct ReminderRootView: View {
    private let store: ReminderStore
    private let scheduler: ReminderNotificationScheduler
    private let owner: MiniAppID
    @Environment(\.miniAppConsentStore) private var consents
    @Environment(\.miniAppLifetime) private var lifetime
    @Environment(\.scenePhase) private var scenePhase

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
            Section {
                TextField(String(localized: "Example: Drink water", bundle: .module), text: $message)
            } header: {
                Text("Message", bundle: .module)
            }

            Section {
                Button {
                    runOwned { await save() }
                } label: {
                    Text("Save", bundle: .module)
                }

                Button {
                    switch consents?.consent(for: owner, permissionID: ReminderNotificationScheduler.permission.id) {
                    case .notDetermined?: requestingConsent = true
                    case .denied?:
                        statusMessage = String(localized: "You denied notifications for Reminder. You can change this in Manage Mini Apps.", bundle: .module)
                        isError = true
                    default: runOwned { await scheduleNotification() }
                    }
                } label: {
                    Text("Notify in 10 Seconds", bundle: .module)
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
        .navigationTitle(Text("Reminder", bundle: .module))
        .task {
            await load()
            try? await scheduler.refreshBadge()
        }
        // Returning to the app does not show this view again, so the reminder
        // delivered meanwhile is cleared here.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { runOwned { try? await scheduler.refreshBadge() } }
        }
        .alert(Text("Reminder Uses Notifications", bundle: .module), isPresented: $requestingConsent) {
            Button {
                consents?.setConsent(.allowed, for: owner, permissionID: ReminderNotificationScheduler.permission.id)
                runOwned { await scheduleNotification() }
            } label: {
                Text("Allow", bundle: .module)
            }
            Button(role: .cancel) {
                consents?.setConsent(.denied, for: owner, permissionID: ReminderNotificationScheduler.permission.id)
            } label: {
                Text("Don’t Allow", bundle: .module)
            }
        } message: {
            let permission = ReminderNotificationScheduler.permission
            Text(String(localized: "\(permission.purpose)\nIf you don’t allow: \(permission.deniedBehavior)", bundle: .module))
        }
    }

    @MainActor
    private func runOwned(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        if let lifetime {
            guard lifetime.isStartAllowed, let runtime = lifetime.runtime else { return }
            do { try runtime.start { await operation() } }
            catch { statusMessage = String(localized: "This app has ended", bundle: .module); isError = true }
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
            statusMessage = String(localized: "Can’t load the saved message", bundle: .module)
            isError = true
        }
    }

    @MainActor
    private func save() async {
        do {
            _ = try await saveCurrentMessage()
            statusMessage = String(localized: "Saved", bundle: .module)
            isError = false
        } catch ReminderInputError.emptyMessage {
            statusMessage = String(localized: "Enter a message", bundle: .module)
            isError = true
        } catch {
            statusMessage = String(localized: "Can’t save the message", bundle: .module)
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
                statusMessage = String(localized: "Scheduled a notification in 10 seconds", bundle: .module)
                isError = false
                try? await scheduler.refreshBadge()
                // Clear the count after delivery while the app stays open.
                try? await Task.sleep(for: .seconds(ReminderNotificationScheduler.delay + 1))
                try? await scheduler.refreshBadge()
            case .denied:
                statusMessage = String(localized: "Notifications aren’t allowed. You can change this in Settings", bundle: .module)
                isError = true
            }
        } catch ReminderInputError.emptyMessage {
            statusMessage = String(localized: "Enter a message", bundle: .module)
            isError = true
        } catch {
            statusMessage = String(localized: "Can’t schedule the notification", bundle: .module)
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
