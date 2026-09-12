#if os(iOS)
import JibunKitCore
import Observation
import SwiftUI

struct MiniAppListScreen: View {
    @Bindable var navigation: AppNavigation
    @State private var showingBackup = false
    @State private var showingManagement = false
    @State private var searchText = ""

    private var matchingApps: [MiniAppDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return MiniAppRegistry.enabled }
        return MiniAppRegistry.enabled.filter {
            $0.title.localizedStandardContains(query)
                || $0.id.rawValue.localizedStandardContains(query)
        }
    }

    var body: some View {
        let owner = navigation.activeID
        NavigationStack(path: navigation.pathBinding) {
            // A disabled owner's presenting root stays mounted until the
            // departure acknowledgement; it is no longer an admitted entry.
            if let owner, let miniApp = MiniAppRegistry.all.first(where: { $0.id == owner }) {
                miniApp.makeDestination()
                    .disabled(!MiniAppRegistry.management.isEnabled(owner))
                    .navigationTitle(miniApp.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if navigation.path.isEmpty {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { navigation.showList() } label: {
                                    Label("ミニアプリ", systemImage: "chevron.left")
                                }
                                .accessibilityLabel("ミニアプリ")
                                .accessibilityIdentifier("miniapp.back-to-list")
                            }
                        }
                    }
            } else {
                launcher
            }
        }
        // Feature-local destination types may be identical in different apps.
        // Rebuild the stack for its owner while retaining that owner's path.
        .id(navigation.stackID)
        .onChange(of: MiniAppRegistry.registeredIDs) { _, _ in navigation.discardUnavailableOwners() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if owner != nil {
                HStack {
                    Spacer()
                    Menu {
                        Button("ミニアプリ一覧", systemImage: "square.grid.2x2") { navigation.showList() }
                            .accessibilityIdentifier("miniapp.switch.list")
                        ForEach(MiniAppRegistry.enabled) { miniApp in
                            Button { navigation.open(miniApp.id) } label: {
                                Label(miniApp.title, systemImage: miniApp.systemImage)
                            }
                            .accessibilityIdentifier("miniapp.switch.\(miniApp.id.rawValue)")
                        }
                        Divider()
                        Button("このアプリの最初の画面へ", systemImage: "arrow.uturn.backward") {
                            navigation.resetCurrentPath()
                        }
                        .accessibilityIdentifier("miniapp.switch.reset")
                    } label: {
                        Label("ミニアプリを切り替え", systemImage: "square.grid.2x2")
                    }
                    .accessibilityIdentifier("miniapp.switch.open")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    private var launcher: some View {
        List {
            ForEach(matchingApps) { miniApp in
                Button { navigation.open(miniApp.id) } label: {
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
            ToolbarItem(placement: .topBarLeading) {
                Button("管理", systemImage: "slider.horizontal.3") { showingManagement = true }
                    .accessibilityIdentifier("management.open")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("バックアップ", systemImage: "externaldrive") { showingBackup = true }
                    .accessibilityIdentifier("backup.open")
            }
        }
        .sheet(isPresented: $showingBackup) { BackupScreen(definitions: MiniAppRegistry.enabled) }
        .sheet(isPresented: $showingManagement) { MiniAppManagementScreen() }
    }
}
#endif
