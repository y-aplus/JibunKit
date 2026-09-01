#if os(iOS)
import AppbaseCore
import Observation

@MainActor
@Observable
final class AppNavigation {
    static let shared = AppNavigation()

    var path: [MiniAppID] = []

    func open(_ miniAppID: MiniAppID) {
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
