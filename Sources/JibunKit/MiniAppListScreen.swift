#if os(iOS)
import JibunKitCore
import Observation
import SwiftUI
import UIKit

struct MiniAppListScreen: View {
    @Bindable var navigation: AppNavigation
    @State private var searchText = ""
    @State private var windowError: String?

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
                Group {
                    if let failure = MiniAppRegistry.launchState.errors[owner] {
                        ContentUnavailableView("Preparation at launch failed", systemImage: "exclamationmark.triangle",
                            description: Text("\(failure)\nFix the registration conditions, then restart the app."))
                            .accessibilityIdentifier("miniapp.launch.error.\(owner.rawValue)")
                    } else {
                        miniApp.makeDestination()
                    }
                }
                    .disabled(!MiniAppRegistry.management.isEnabled(owner))
                    .navigationTitle(miniApp.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if navigation.path.isEmpty {
                            ToolbarItem(placement: .topBarLeading) {
                                // Tap returns to the list; a long press switches
                                // Features. The host keeps the bottom edge free.
                                Menu {
                                    Button("All Mini Apps", systemImage: "square.grid.2x2") { navigation.showList() }
                                        .accessibilityIdentifier("miniapp.switch.list")
                                    Section("Switch") {
                                        ForEach(MiniAppRegistry.enabled.filter { $0.id != owner }) { other in
                                            Button { navigation.open(other.id) } label: {
                                                Label(other.title, systemImage: other.systemImage)
                                            }
                                            .accessibilityIdentifier("miniapp.switch.\(other.id.rawValue)")
                                        }
                                    }
                                } label: {
                                    Label("Mini Apps", systemImage: "chevron.left")
                                } primaryAction: {
                                    navigation.showList()
                                }
                                .accessibilityLabel("Mini Apps")
                                .accessibilityHint("Touch and hold to switch to another mini app.")
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
        .alert("Couldn’t Open a Window", isPresented: Binding(
            get: { windowError != nil }, set: { if !$0 { windowError = nil } }
        )) {
            Button("Close", role: .cancel) { windowError = nil }
        } message: { Text(windowError ?? "") }
        .sheet(item: $navigation.hostSheet, onDismiss: navigation.hostSheetDidDismiss) { sheet in
            switch sheet {
            case .backup: BackupScreen(definitions: MiniAppRegistry.enabled,
                                      lifecycleForDefinition: { MiniAppWindowOwnership.restoreLifecycle(for: $0) })
            case .management: MiniAppManagementScreen()
            case .incoming: MiniAppIncomingScreen(navigation: navigation)
            case .search: MiniAppSearchContinuationScreen(navigation: navigation)
            }
        }
    }

    private var launcher: some View {
        List {
            if let failure = MiniAppRegistry.launchState.hostError {
                Text("Setup at launch failed: \(failure)").foregroundStyle(.red)
            }
            ForEach(matchingApps) { miniApp in
                Button { navigation.open(miniApp.id) } label: {
                    VStack(alignment: .leading) {
                        Label(miniApp.title, systemImage: miniApp.systemImage)
                        if let failure = MiniAppRegistry.launchState.errors[miniApp.id] {
                            Text("Preparation failed: \(failure)").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                .accessibilityIdentifier("miniapp.\(miniApp.id.rawValue)")
            }
        }
        .navigationTitle("Mini Apps")
        .searchable(text: $searchText, prompt: "Search by app name or ID")
        .overlay {
            if matchingApps.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Manage", systemImage: "slider.horizontal.3") { navigation.requestHostSheet(.management) }
                    .accessibilityIdentifier("management.open")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Backup", systemImage: "externaldrive") { navigation.requestHostSheet(.backup) }
                    .accessibilityIdentifier("backup.open")
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Inbox", systemImage: "tray.and.arrow.down") { navigation.requestHostSheet(.incoming) }
                    .accessibilityIdentifier("incoming.open")
            }
            if UIApplication.shared.supportsMultipleScenes {
                ToolbarItem(placement: .bottomBar) {
                    Button("New Window", systemImage: "rectangle.badge.plus") {
                        MiniAppUIKitWindowSceneRequester().requestWindow(userActivity: nil) {
                            windowError = $0.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("window.new")
                }
            }
        }
    }
}
#endif
