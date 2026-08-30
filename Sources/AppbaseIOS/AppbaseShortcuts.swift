#if os(iOS)
import AppIntents

struct AppbaseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddCounterValueIntent(),
            phrases: [
                "\(.applicationName)のカウンターに追加",
            ],
            shortTitle: "カウンターに追加",
            systemImageName: "plus.circle"
        )
    }
}
#endif
