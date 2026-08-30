#if os(iOS)
import SwiftUI

@main
struct AppbaseIOSApp: App {
    var body: some Scene {
        WindowGroup {
            CounterScreen()
        }
    }
}
#endif
