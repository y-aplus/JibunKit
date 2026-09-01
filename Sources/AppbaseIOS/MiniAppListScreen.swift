#if os(iOS)
import SwiftUI

struct MiniAppListScreen: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CounterScreen()
                } label: {
                    Label("カウンター", systemImage: "number")
                }
            }
            .navigationTitle("ミニアプリ")
        }
    }
}
#endif
