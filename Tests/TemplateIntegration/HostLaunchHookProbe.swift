// Included only in the isolated signed CI host, never in a distributed IPA.
import JibunKitCore
import SwiftUI

@MainActor
enum HostLaunchHookProbe {
    private static var launchCounts: [MiniAppID: Int] = [:]
    private static var rootCreations = 0

    static let definitions = [
        definition(id: "host-launch-a", title: "Host launch A"),
        definition(id: "host-launch-b", title: "Host launch B"),
    ]

    private static func definition(id: String, title: String) -> MiniAppDefinition {
        let owner = MiniAppID(id)
        return MiniAppDefinition(
            id: owner,
            title: title,
            systemImage: "bolt",
            onHostLaunch: {
                precondition(rootCreations == 0, "Registration must precede every Feature root")
                precondition(launchCounts[owner, default: 0] == 0,
                             "Host launch registration ran more than once for \(owner.rawValue)")
                launchCounts[owner, default: 0] += 1
            }
        ) { _ in
            rootCreations += 1
            return Text(String(launchCounts[owner, default: 0]))
                .accessibilityIdentifier("host.launch.\(owner.rawValue).count")
        }
    }
}
