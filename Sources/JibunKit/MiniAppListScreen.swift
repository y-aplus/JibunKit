#if os(iOS)
import JibunKitCore
import Observation
import SwiftUI

struct MiniAppListScreen: View {
    @Bindable var navigation: AppNavigation

    var body: some View {
        NavigationStack(path: $navigation.path) {
            List {
                ForEach(MiniAppID.allCases, id: \.self) { miniAppID in
                    NavigationLink(value: miniAppID) {
                        Label(miniAppID.title, systemImage: miniAppID.systemImage)
                    }
                }
            }
            .navigationTitle("ミニアプリ")
            .navigationDestination(for: MiniAppID.self) { miniAppID in
                switch miniAppID {
                case .counter:
                    CounterScreen()
                case .reminder:
                    ReminderScreen()
                }
            }
        }
    }
}

private extension MiniAppID {
    var title: String {
        switch self {
        case .counter:
            "カウンター"
        case .reminder:
            "リマインダー"
        }
    }

    var systemImage: String {
        switch self {
        case .counter:
            "number"
        case .reminder:
            "bell"
        }
    }
}
#endif
