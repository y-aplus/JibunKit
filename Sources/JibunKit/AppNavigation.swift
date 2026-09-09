#if os(iOS)
import JibunKitCore
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppNavigation {
    static let shared = AppNavigation()

    var path = NavigationPath()

    func openURL(_ url: URL) {
        guard let route = MiniAppLink.resolveRoute(url, registeredIDs: MiniAppRegistry.registeredIDs) else { return }
        if let destination = route.destination {
            guard let next = MiniAppRegistry.definition(for: route.id)?.navigationPath(for: destination) else { return }
            path = next
        } else {
            open(route.id)
        }
    }

    func open(_ miniAppID: MiniAppID) {
        guard MiniAppRegistry.registeredIDs.contains(miniAppID) else {
            path = NavigationPath()
            return
        }
        path = NavigationPath([miniAppID])
    }

    func openNotificationTarget(_ miniAppID: MiniAppID?) {
        guard let miniAppID else {
            path = NavigationPath()
            return
        }
        open(miniAppID)
    }
}
#endif
