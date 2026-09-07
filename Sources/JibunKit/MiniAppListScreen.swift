#if os(iOS)
import JibunKitCore
import Observation
import SwiftUI

struct MiniAppListScreen: View {
    @Bindable var navigation: AppNavigation
    @State private var showingBackup = false

    var body: some View {
        NavigationStack(path: $navigation.path) {
            List {
                ForEach(MiniAppRegistry.all) { miniApp in
                    NavigationLink(value: miniApp.id) {
                        Label(miniApp.title, systemImage: miniApp.systemImage)
                    }
                    .accessibilityIdentifier("miniapp.\(miniApp.id.rawValue)")
                }
            }
            .navigationTitle("ミニアプリ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("バックアップ", systemImage: "externaldrive") { showingBackup = true }
                        .accessibilityIdentifier("backup.open")
                }
            }
            .sheet(isPresented: $showingBackup) { BackupScreen() }
            .navigationDestination(for: MiniAppID.self) { miniAppID in
                if let miniApp = MiniAppRegistry.definition(for: miniAppID) {
                    miniApp.makeDestination()
                        .navigationTitle(miniApp.title)
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    ContentUnavailableView(
                        "ミニアプリを開けません",
                        systemImage: "questionmark.app"
                    )
                }
            }
        }
    }
}
#endif
