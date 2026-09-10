// Native search-result routing fixture; copied only into the isolated CI host.
import CoreSpotlight
import JibunKitCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

private struct SpotlightProbeDestination: Hashable { let value: String }

@MainActor
@Observable
private final class SpotlightRoutingState {
    let title: String
    var status = "idle"
    init(owner: String) { title = "JK \(owner) \(UUID().uuidString.prefix(8))" }

    func index(context: MiniAppContext) async {
        let started = Date()
        status = "indexing"
        do {
            let namespace = MiniAppSpotlightNamespace(context: context)
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = title
            attributes.contentDescription = "JibunKit native search route probe"
            try await namespace.index(localIdentifier: "detail", attributes: attributes, in: .default())
            status = "querying"
            print("SPOTLIGHT_ROUTE owner=\(context.id) indexed elapsed=\(Date().timeIntervalSince(started))")
            // Observe actual native query visibility before moving to SpringBoard.
            _ = try await SpotlightOwnershipProbe.queryEventually(
                titles: [title], expectedIdentifiers: [namespace.itemIdentifier(for: "detail")])
            status = "ready"
            print("SPOTLIGHT_ROUTE owner=\(context.id) ready elapsed=\(Date().timeIntervalSince(started))")
        } catch { status = "failed: \(error)" }
    }

    func clear() async {
        do {
            for id in ["spotlight-link-a", "spotlight-link-b"] {
                try await MiniAppSpotlightNamespace(context: MiniAppContext(id: MiniAppID(id))).deleteAll(from: .default())
            }
            status = "removed"
        } catch { status = "failed: \(error)" }
    }
}

@MainActor
enum SpotlightRoutingProbe {
    private static let first = SpotlightRoutingState(owner: "Alpha")
    private static let second = SpotlightRoutingState(owner: "Beta")
    static let definitions = [definition("spotlight-link-a", first), definition("spotlight-link-b", second)]

    private static func definition(_ id: String, _ state: SpotlightRoutingState) -> MiniAppDefinition {
        MiniAppDefinition(id: MiniAppID(id), title: id, systemImage: "magnifyingglass",
            appendDestination: { localID, path in
                guard localID == "detail" else { return false }
                path.append(SpotlightProbeDestination(value: localID))
                return true
            }) { context in
                VStack {
                    Text(state.title).accessibilityIdentifier("spotlight.route.title")
                    Text(state.status).accessibilityIdentifier("spotlight.route.status")
                    Button("Index searchable item") { Task { await state.index(context: context) } }
                        .accessibilityIdentifier("spotlight.route.index")
                    NavigationLink("Open manual detail", value: SpotlightProbeDestination(value: "manual"))
                        .accessibilityIdentifier("spotlight.route.manual")
                }
                .navigationDestination(for: SpotlightProbeDestination.self) { destination in
                    VStack {
                        Text("\(id):\(destination.value)").accessibilityIdentifier("spotlight.route.destination")
                        Button("Remove probe items") { Task { await state.clear() } }
                            .accessibilityIdentifier("spotlight.route.clear")
                        Text(state.status).accessibilityIdentifier("spotlight.route.status")
                    }
                }
            }
    }
}
