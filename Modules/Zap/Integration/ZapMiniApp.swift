#if os(iOS)
import JibunKitCore
import ZapFeature

/// Connects Zap to the JibunKit host. Written by `jibunkit-feature.py migrate`;
/// JibunKitFeature.json lists this directory, so the host app compiles it.
@MainActor
enum ZapMiniApp {
    static let definition = MiniAppDefinition(
        id: MiniAppID("zap"),
        title: "Zap Notes",
        systemImage: "square.grid.2x2"
    ) { _ in
        ZapRootView()
    }
}
#endif
