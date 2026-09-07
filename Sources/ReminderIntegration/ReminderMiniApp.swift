import JibunKitCore
import ReminderFeature

#if os(iOS)
public enum ReminderMiniApp {
    @MainActor
    public static let definition = MiniAppDefinition(
        id: .reminder,
        title: "リマインダー",
        systemImage: "bell",
        backup: ReminderStore.shared.backupProvider
    ) { context in
        ReminderRootView(context: context)
    }
}
#endif
