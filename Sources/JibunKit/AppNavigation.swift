#if os(iOS)
import JibunKitCore
import Foundation
import Observation

@MainActor
@Observable
final class AppNavigation {
    static let shared = AppNavigation()

    var path: [MiniAppID] = []

    func openURL(_ url: URL) {
        guard let id = MiniAppLink.resolve(url, registeredIDs: MiniAppRegistry.registeredIDs) else { return }
        open(id)
    }

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
