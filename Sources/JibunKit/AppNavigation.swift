#if os(iOS)
import JibunKitCore
import Observation

@MainActor
@Observable
final class AppNavigation {
    static let shared = AppNavigation()

    var path: [MiniAppID] = []

    func open(_ miniAppID: MiniAppID) {
        guard MiniAppRegistry.registeredIDs.contains(miniAppID) else {
            path = []
            return
        }
        path = [miniAppID]
    }

    func openNotificationTarget(_ miniAppID: MiniAppID?) {
        guard let miniAppID else {
            path = []
            return
        }
        open(miniAppID)
    }
}
#endif
