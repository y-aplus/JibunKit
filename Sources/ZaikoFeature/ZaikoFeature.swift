import JibunKitCore
import Foundation

public extension MiniAppID {
    static let zaiko = MiniAppID("zaiko")
}

#if os(iOS)
public enum ZaikoMiniApp {
    @MainActor
    public static let definition = MiniAppDefinition(
        id: .zaiko,
        title: "在庫管理",
        systemImage: "shippingbox"
    ) { context in
        ZaikoRootView(context: context)
    }
}
#endif
