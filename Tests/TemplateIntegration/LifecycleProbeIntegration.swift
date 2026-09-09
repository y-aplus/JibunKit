// Included only in the isolated CI host, never in a distributed IPA.
import SwiftUI
import Observation
import JibunKitCore

@MainActor
@Observable
final class LifecycleProbeState {
    var events: [String] = []
    func receive(_ phase: MiniAppHostPhase) {
        switch phase {
        case .active: events.append("active")
        case .inactive: events.append("inactive")
        case .background: events.append("background")
        }
    }
}

@MainActor
enum LifecycleProbeIntegration {
    private static let first = LifecycleProbeState()
    private static let second = LifecycleProbeState()
    static let definitions = [definition("lifecycle-a", state: first), definition("lifecycle-b", state: second)]

    private static func definition(_ id: String, state: LifecycleProbeState) -> MiniAppDefinition {
        MiniAppDefinition(id: MiniAppID(id), title: id, systemImage: "clock",
                          onHostPhaseChange: { state.receive($0) }) { _ in
            Text(state.events.joined(separator: ","))
                .accessibilityIdentifier("lifecycle.events")
        }
    }
}
