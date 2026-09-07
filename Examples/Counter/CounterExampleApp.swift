import CounterFeature
import JibunKitCore
import SwiftUI

@main
struct CounterExampleApp: App {
    private let store = CounterStore(
        context: MiniAppContext(id: .counter),
        suiteName: nil
    )

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                CounterRootView(store: store)
                    .navigationTitle("カウンター単独実行")
            }
        }
    }
}
