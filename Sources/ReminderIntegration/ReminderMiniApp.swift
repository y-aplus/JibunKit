import JibunKitCore
import ReminderFeature

#if os(iOS)
public enum ReminderMiniApp {
    @MainActor
    public static let lifetime = MiniAppFeatureLifetime(id: .reminder)

    @MainActor
    public static let definition = MiniAppDefinition(
        id: .reminder,
        title: "リマインダー",
        systemImage: "bell",
        backup: ReminderStore.shared.backupProvider,
        lifetime: lifetime,
        removal: ReminderStore.shared.removalProvider,
        permissions: [ReminderNotificationScheduler.permission]
    ) { context in
        ReminderRootView(context: context)
    }
}
#endif
