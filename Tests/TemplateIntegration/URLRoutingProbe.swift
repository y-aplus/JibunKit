// Copied only into the isolated generated host, never the distributed app.
import JibunKitCore
import SwiftUI

private struct URLProbeDestination: Hashable { let value: String }

@MainActor
enum URLRoutingProbe {
    static let definitions = [definition("url-a"), definition("url-b")]

    private static func definition(_ id: String) -> MiniAppDefinition {
        MiniAppDefinition(id: MiniAppID(id), title: id, systemImage: "link",
            appendDestination: { value, path in
                guard value == "detail" else { return false }
                path.append(URLProbeDestination(value: value))
                return true
            },
            resolveIncomingURL: { url in
                guard url.scheme == "jkrouteprobe", url.user == nil, url.password == nil,
                      url.port == nil, url.query == nil, url.fragment == nil else { return nil }
                if url.host == "ambiguous" { return .root }
                guard url.host == id else { return nil }
                switch url.path {
                case "/": return .root
                case "/detail": return .detail("detail")
                case "/invalid-destination": return .detail("not-found")
                default: return nil
                }
            }) { _ in
                VStack {
                    Text("\(id):root").accessibilityIdentifier("url.route.location")
                    NavigationLink("Manual detail", value: URLProbeDestination(value: "manual"))
                        .accessibilityIdentifier("url.route.manual")
                }
                .navigationDestination(for: URLProbeDestination.self) { destination in
                    Text("\(id):\(destination.value)").accessibilityIdentifier("url.route.location")
                }
            }
    }
}
