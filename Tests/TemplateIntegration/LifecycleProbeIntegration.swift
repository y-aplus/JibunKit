// Included only in the isolated CI host, never in a distributed IPA.
import SwiftUI
import Observation
import JibunKitCore
import UserNotifications

@MainActor
@Observable
final class LifecycleProbeState {
    var events: [String] = []
    var taskStatus = "idle"
    var categories = "unread"
    var foregroundCount = 0
    var lastAction = "none"
    var scheduleStatus = "idle"

    func schedule(context: MiniAppContext, action: Bool = false) async {
        do {
            let center = UNUserNotificationCenter.current()
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                scheduleStatus = "denied"
                return
            }
            let content = UNMutableNotificationContent()
            content.title = action ? "Action-" + context.id.rawValue : context.id.rawValue
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
    private let scope = MiniAppTaskScope()
    private var input: AsyncStream<Void>.Continuation?

    func start() {
        guard taskStatus != "running" else { return }
        let channel = AsyncStream<Void>.makeStream()
        input = channel.continuation
        taskStatus = "running"
        scope.start { [weak self] in
            for await _ in channel.stream { }
            await self?.finish(cancelled: Task.isCancelled)
        }
    }

    func cancel() { scope.cancelAll() }
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
        return MiniAppDefinition(id: context.id, title: id, systemImage: "clock",
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
                    try store.set(Data(context.id.rawValue.utf8), for: "same-account")
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

    private func perform(_ operation: () throws -> String) {
        do { result = try operation() }
        catch { result = "error: \(error)" }
    }
}
