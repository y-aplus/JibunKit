import SwiftUI
import LocationCheckFeature

@main
struct LocationCheckExampleApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack { LocationCheckRootView() }
        }
    }
}
