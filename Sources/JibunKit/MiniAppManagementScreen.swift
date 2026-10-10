#if os(iOS)
import JibunKitCore
import SwiftUI

struct MiniAppManagementScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: MiniAppDefinition?
    @State private var errorMessage: String?
    private let management = MiniAppRegistry.management

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section("Couldn’t Complete") {
                        Text(errorMessage).foregroundStyle(.red)
                            .accessibilityIdentifier("management.error")
                    }
                }
                ForEach(MiniAppRegistry.all) { definition in
                    Section {
                        if let failure = MiniAppRegistry.launchState.errors[definition.id] {
                            Text("Registration at launch failed: \(failure)").foregroundStyle(.red)
                            Text("Enabling doesn’t register again. Fix the registration conditions, then restart the app.")
                                .font(.caption)
                        }
                        Text(statusText(management.status(for: definition.id)))
                            .accessibilityIdentifier("management.status.\(definition.id.rawValue)")
                        if let failure = management.failures[definition.id] {
                            Text("Failed at step: \(stageText(failure.stage)). \(failure.message)")
                                .foregroundStyle(.red)
                        }
                        if let failure = MiniAppRegistry.continuingStatus.errors[definition.id],
                           management.isEnabled(definition.id) {
                            Text("Can’t confirm the ongoing activity. \(failure)")
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("management.continuing.error.\(definition.id.rawValue)")
                            Button("Check Again") {
                                MiniAppRegistry.reconcileContinuingSurfaces(for: definition.id)
                            }
                            .disabled(MiniAppRegistry.continuingStatus.pending.contains(definition.id)
                                || management.stages[definition.id] != nil)
                        }
                        if let stage = management.stages[definition.id] {
                            ProgressView(stageText(stage))
                            if stage == .stopping, let runtime = definition.lifetime?.runtime {
                                TimelineView(.periodic(from: .now, by: 1)) { _ in
                                    let progress = runtime.shutdownProgress
                                    Text("Waiting to finish: \(progress.pendingTaskCount) tasks, \(progress.remainingCleanupCount) cleanups")
                                        .font(.caption)
                                }
                            }
                        } else {
                            actions(for: definition)
                        }
                        ForEach(definition.permissions) { permission in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(permission.title).font(.headline)
                                Text(permission.purpose)
                                Text("If denied: \(permission.deniedBehavior)").font(.caption)
                                Picker("Use in This App", selection: Binding(
                                    get: { MiniAppRegistry.consents.consent(for: definition.id, permissionID: permission.id) },
                                    set: { consent in
                                        do {
                                            try definition.setConsent(consent, permissionID: permission.id,
                                                                      in: MiniAppRegistry.consents)
                                            errorMessage = nil
                                        } catch { errorMessage = String(describing: error) }
                                    }
                                )) {
                                    Text("Not Determined").tag(MiniAppConsent.notDetermined)
                                    Text("Allow").tag(MiniAppConsent.allowed)
                                    Text("Deny").tag(MiniAppConsent.denied)
                                }
                                .pickerStyle(.menu)
                                .accessibilityIdentifier("management.consent.\(definition.id.rawValue).\(permission.id)")
                                .disabled(!management.isEnabled(definition.id))
                            }
                        }
                    } header: {
                        Label(definition.title, systemImage: definition.systemImage)
                    }
                }
                Section {
                    Text("Consent is saved for each mini app. iOS permissions are shared by all of JibunKit and aren’t changed by allowing here.")
                    Text("Deleting removes the registration and owned data. Removing the built-in code requires a rebuild.")
                }
            }
            .accessibilityIdentifier("management.list")
            .navigationTitle("Manage Mini Apps")
            .toolbar { Button("Close") { dismiss() }.disabled(!management.stages.isEmpty) }
            .interactiveDismissDisabled(!management.stages.isEmpty)
            .alert("Delete owned data?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), presenting: deleting) { definition in
                Button("Cancel", role: .cancel) { deleting = nil }
                Button("Delete", role: .destructive) {
                    deleting = nil
                    perform { try await management.remove(definition.id) }
                }
            } message: { definition in
                Text("\(definition.title): \(definition.removal?.dataDescription ?? "")\nNotification and search registrations and consent are also deleted. Other mini apps’ data isn’t changed.")
            }
        }
    }

    @ViewBuilder
    private func actions(for definition: MiniAppDefinition) -> some View {
        let status = management.status(for: definition.id)
        if status == .enabled || status == .disabling {
            Button(status == .disabling ? "Retry Disabling" : "Disable (Keep Data)" as LocalizedStringKey) {
                perform { try await management.disable(definition.id) }
            }
            .accessibilityIdentifier("management.disable.\(definition.id.rawValue)")
        } else if status == .disabled || status == .removed {
            Button(status == .removed ? "Register from Scratch" : "Enable Again" as LocalizedStringKey) {
                perform { try await management.enable(definition.id) }
            }
            .accessibilityIdentifier("management.enable.\(definition.id.rawValue)")
        }
        if status != .removed {
            if management.canRemove(definition.id) {
                Button(status == .removing ? "Retry Deleting" : "Delete Registration and Owned Data" as LocalizedStringKey, role: .destructive) {
                    deleting = definition
                }
                .accessibilityIdentifier("management.delete.\(definition.id.rawValue)")
            } else {
                Text("This app hasn’t declared the data to delete yet. Disabling is available.")
                    .font(.caption)
            }
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        errorMessage = nil
        // The operation outlives the button/view; management persists its intent.
        Task { @MainActor in
            do { try await operation() }
            catch let failure as MiniAppManagement.Failure { errorMessage = failure.message }
            catch { errorMessage = String(describing: error) }
        }
    }

    private func statusText(_ status: MiniAppManagement.Status?) -> String {
        switch status {
        case .enabled: String(localized: "Enabled")
        case .disabled: String(localized: "Disabled (Data Kept)")
        case .removed: String(localized: "Deleted")
        case .disabling: String(localized: "Disabling isn’t complete. New launches are stopped.")
        case .removing: String(localized: "Deleting isn’t complete. Retry to finish the remaining work.")
        case nil: String(localized: "Not Registered")
        }
    }

    private func stageText(_ stage: MiniAppManagement.Stage) -> String {
        switch stage {
        case .reservation: String(localized: "Checking storage use")
        case .externalAccess: String(localized: "Accepting requests from widgets and extensions")
        case .stopping: String(localized: "Ending owned work")
        case .unregistering: String(localized: "Unregistering notifications, search and more")
        case .deletingData: String(localized: "Deleting owned data")
        case .clearingConsent: String(localized: "Deleting consent")
        case .enabling: String(localized: "Enabling registrations again")
        }
    }
}
#endif
