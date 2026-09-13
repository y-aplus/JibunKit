// Copied only into an isolated 0.8 candidate host; never included in the normal 0.7 product.
#if os(iOS)
import JibunKitCore
import P1WidgetFeatureA
import P1WidgetFeatureB

@MainActor
enum P1WidgetsProbe {
    private static let aStore = FeatureAStore()
    private static let bStore = FeatureBStore()

    /// Add these Definitions to the existing MiniAppRegistry.all array. The registry's
    /// one normal MiniAppManagement then owns disable/remove/re-enable for both probes.
    static let definitions = [
        FeatureAMiniApp.definition(store: aStore),
        FeatureBMiniApp.definition(store: bStore),
    ]
}
#endif
