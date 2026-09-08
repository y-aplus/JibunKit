#if os(iOS)
import JibunKitCore
import Observation
import SwiftUI

struct MiniAppListScreen: View {
    @Bindable var navigation: AppNavigation
    @State private var showingBackup = false
    @State private var searchText = ""

    private var matchingApps: [MiniAppDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return MiniAppRegistry.all }
        return MiniAppRegistry.all.filter {
            $0.title.localizedStandardContains(query)
                || $0.id.rawValue.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack(path: $navigation.path) {
            List {
                ForEach(matchingApps) { miniApp in
                    NavigationLink(value: miniApp.id) {
                        Label(miniApp.title, systemImage: miniApp.systemImage)
                    }
                    .accessibilityIdentifier("miniapp.\(miniApp.id.rawValue)")
                }
            }
            .navigationTitle("ミニアプリ")
            .searchable(text: $searchText, prompt: "アプリ名・IDで検索")
            .overlay {
                if matchingApps.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
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
