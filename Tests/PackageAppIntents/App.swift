import SwiftUI
@main
@MainActor
struct IntentFixtureApp: App {
    init() { IntentFixtureBootstrap.start() }
    var body: some Scene { WindowGroup { IntentFixtureRootView() } }
}
