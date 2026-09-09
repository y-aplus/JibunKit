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
                          notificationCategories: [category(context, key: "initial")]) { _ in
            VStack {
                Text(state.events.joined(separator: ","))
                    .accessibilityIdentifier("lifecycle.events")
                Text(state.categories).accessibilityIdentifier("notification.categories")
                Button("Read categories") { Task { await state.readCategories() } }
                    .accessibilityIdentifier("notification.read")
                Button("Replace categories") { Task { await state.replaceCategories(context: context, key: "updated") } }
                    .accessibilityIdentifier("notification.replace")
                Button("Remove categories") { Task { await state.replaceCategories(context: context, key: nil) } }
                    .accessibilityIdentifier("notification.remove")
                Text(state.taskStatus).accessibilityIdentifier("lifecycle.task.status")
                Button("Start", action: state.start).accessibilityIdentifier("lifecycle.task.start")
                Button("Cancel", action: state.cancel).accessibilityIdentifier("lifecycle.task.cancel")
                Button("Complete", action: state.complete).accessibilityIdentifier("lifecycle.task.complete")
            }
        }
    }
}
