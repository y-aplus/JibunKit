#if os(iOS)
import SwiftUI

@main
struct JibunKitApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self)
    private var notificationAppDelegate
    @State private var navigation = AppNavigation.shared

    var body: some Scene {
        WindowGroup {
            MiniAppListScreen(navigation: navigation)
        }
    }
}
#endif
