#if os(iOS)
import SwiftUI
import JibunKitCore

struct MiniAppIncomingScreen: View {
    @Bindable var navigation: AppNavigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var rows: [Row] = []
    @State private var message: String?
    @State private var operation: Task<Void, Never>?
    @State private var discardTarget: Row?

    private struct Row: Identifiable {
        let id: UUID
        let owner: MiniAppID
        let receipt: MiniAppIncomingReceipt?
    }

    private var destinations: [MiniAppDefinition] {
        guard let prepared = navigation.preparedIncoming else { return [] }
        return MiniAppRegistry.enabled.filter { definition in
            guard let destination = MiniAppRegistry.incomingDestination(for: definition) else { return false }
            return prepared.inputs.allSatisfy { destination.accepts($0.typeIdentifier) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if navigation.isPreparingIncoming {
                    ProgressView("Loading the file")
                    Button("Cancel Loading") { navigation.discardPreparedIncoming() }
                }
                if let error = navigation.incomingError { Text(error).foregroundStyle(.red) }
                if let message { Text(message).accessibilityIdentifier("incoming.message") }
                if let prepared = navigation.preparedIncoming {
                    Section("Choose a Destination (\(prepared.inputs.count))") {
                        if destinations.isEmpty { Text("No enabled mini app can receive this input.") }
                        ForEach(destinations) { definition in
                            Button(definition.title) { savePrepared(for: definition.id) }
                                .accessibilityIdentifier("incoming.destination.\(definition.id.rawValue)")
                                .disabled(operation != nil)
                        }
                        Button("Cancel Receiving", role: .cancel) { navigation.discardPreparedIncoming() }
                            .disabled(operation != nil)
                    }
                }
                Section("Not Imported") {
                    if rows.isEmpty { Text("No shared data is waiting to be imported.") }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(MiniAppRegistry.all.first(where: { $0.id == row.owner })?.title ?? row.owner.rawValue)
                                .font(.headline)
                            if let receipt = row.receipt {
                                Text(receipt.items.map(\.displayName).formatted(.list(type: .and)))
                                Text(receipt.createdAt, style: .date).font(.caption)
                                if MiniAppRegistry.management.isEnabled(row.owner),
                                   MiniAppRegistry.definition(for: row.owner)?.incoming != nil {
                                    Button("Import / Retry") { deliver(row) }
                                        .accessibilityIdentifier("incoming.apply.\(row.owner.rawValue)")
                                } else { Text("The destination is disabled or not registered in this version. The data is kept.") }
                            } else { Text("Can’t read the received data. You can discard the damaged item.") }
                            Button("Discard", role: .destructive) { discardTarget = row }
                                .accessibilityIdentifier("incoming.discard.\(row.owner.rawValue)")
                        }
                        // Each action belongs to its own control. List's automatic
                        // row button style otherwise activates both receive and discard.
                        .buttonStyle(.bordered)
                        .disabled(operation != nil)
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(operation != nil || navigation.preparedIncoming != nil || navigation.isPreparingIncoming)
                }
                if operation != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Cancel Operation") { operation?.cancel() }
                    }
                }
            }
            .alert("Discard this unimported data?", isPresented: Binding(
                get: { discardTarget != nil }, set: { if !$0 { discardTarget = nil } }
            ), presenting: discardTarget) { target in
                Button("Discard Data", role: .destructive) { discard(target) }
                Button("Cancel", role: .cancel) { discardTarget = nil }
            } message: { _ in Text("Imported mini app data and other received items aren’t changed.") }
            .task { await reload() }
            .refreshable { await reload() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reload() } } }
        }
        .interactiveDismissDisabled(operation != nil || navigation.preparedIncoming != nil || navigation.isPreparingIncoming)
    }

    private func reload() async {
        do {
            let inbox = try MiniAppRegistry.incomingStore.get()
            let (listings, failures) = try await Task.detached {
                var listings: [(MiniAppID, MiniAppIncomingStore.Listing)] = []
                var failures: [String] = []
                for owner in try inbox.ownersWithReceipts() {
                    do { listings.append((owner, try inbox.pending(for: owner))) }
                    catch { failures.append("\(owner.rawValue): \(error.localizedDescription)") }
                }
                return (listings, failures)
            }.value
            rows = listings.flatMap { owner, listing in
                listing.receipts.map { Row(id: $0.id, owner: owner, receipt: $0) }
                    + listing.unreadableIDs.map { Row(id: $0, owner: owner, receipt: nil) }
            }
            if let error = MiniAppRegistry.incomingCatalogError { message = String(localized: "Updating the destinations failed: \(error)") }
            if !failures.isEmpty {
                let list = failures.formatted(.list(type: .and))
                message = String(localized: "Some destinations can’t be read: \(list)")
            }
        } catch { message = error.localizedDescription }
    }

    private func savePrepared(for owner: MiniAppID) {
        guard operation == nil, let prepared = navigation.preparedIncoming else { return }
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                guard MiniAppRegistry.management.isEnabled(owner) else { throw MiniAppIncomingError.unavailableOwner(owner.rawValue) }
                let inbox = try MiniAppRegistry.incomingStore.get()
                let task = Task.detached { try inbox.enqueue(for: owner, inputs: prepared.inputs) }
                _ = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                navigation.discardPreparedIncoming()
                message = String(localized: "Saved. Import it with “Import / Retry” on its item.")
                await reload()
            } catch is CancellationError { message = String(localized: "Canceled. The destination wasn’t changed.") }
            catch { message = error.localizedDescription }
        }
    }

    private func deliver(_ row: Row) {
        guard operation == nil, let definition = MiniAppRegistry.definition(for: row.owner), let provider = definition.incoming else { return }
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                guard MiniAppRegistry.management.isEnabled(row.owner) else { throw MiniAppIncomingError.unavailableOwner(row.owner.rawValue) }
                try await MiniAppIncomingDelivery.shared.deliver(id: row.id, provider: provider,
                    lifetime: definition.lifetime, inbox: MiniAppRegistry.incomingStore.get())
                message = String(localized: "Imported.")
            } catch is CancellationError { message = String(localized: "Canceled. The unfinished item is kept.") }
            catch {
                let reason = error.localizedDescription
                message = String(localized: "Import failed. The item is kept: \(reason)")
            }
            await reload()
        }
    }

    private func discard(_ row: Row) {
        guard operation == nil else { return }
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                let inbox = try MiniAppRegistry.incomingStore.get()
                try await MiniAppIncomingDelivery.shared.discard(id: row.id, owner: row.owner, inbox: inbox)
                message = String(localized: "Discarded the unimported data.")
            } catch { message = error.localizedDescription }
            await reload()
        }
    }
}
#endif
