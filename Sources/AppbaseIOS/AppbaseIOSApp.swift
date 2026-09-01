#if os(iOS)
import SwiftUI

@main
struct AppbaseIOSApp: App {
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
