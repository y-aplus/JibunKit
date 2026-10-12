#if os(iOS)
import JibunKitCore
import VerletFeature

/// Connects Verlet to the JibunKit host. Written by `jibunkit-feature.py migrate`;
/// JibunKitFeature.json lists this directory, so the host app compiles it.
@MainActor
enum VerletMiniApp {
    static let definition = MiniAppDefinition(
        id: MiniAppID("verlet"),
        title: "My App",
        systemImage: "square.grid.2x2"
    ) { _ in
        VerletRootView()
    }
}
#endif
