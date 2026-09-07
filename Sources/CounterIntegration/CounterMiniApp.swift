import JibunKitCore
import CounterFeature

#if os(iOS)
public enum CounterMiniApp {
    @MainActor
    public static let definition = MiniAppDefinition(
        id: .counter,
        title: "カウンター",
        systemImage: "number",
        backup: CounterStore.shared.backupProvider
    ) { context in
        CounterRootView(context: context)
    }
}
#endif
