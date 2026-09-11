// Included only in the isolated signed CI host, never in a distributed IPA.
import JibunKitCore
import SwiftUI

@MainActor
enum HostLaunchHookProbe {
    private static var launchCounts: [MiniAppID: Int] = [:]

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
                precondition(launchCounts[owner, default: 0] == 0,
                             "Host launch registration ran more than once for \(owner.rawValue)")
                launchCounts[owner, default: 0] += 1
            }
        ) { _ in
            Text(String(launchCounts[owner, default: 0]))
                .accessibilityIdentifier("host.launch.\(owner.rawValue).count")
        }
    }
}

