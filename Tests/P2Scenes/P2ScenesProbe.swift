#if os(iOS)
import JibunKitCore
import SwiftUI
import UIKit

/// Two ordinary Feature definitions used by the P2 scene host. The host must
/// include these in its normal registry; the probe does not create a parallel
/// navigation implementation.
@MainActor
enum P2ScenesProbe {
    static let firstID = MiniAppID("p2-scene-a")
    static let secondID = MiniAppID("p2-scene-b")

    static var definitions: [MiniAppDefinition] {
        [definition(id: firstID, title: "Scene A"), definition(id: secondID, title: "Scene B")]
    }

    private static func definition(id: MiniAppID, title: String) -> MiniAppDefinition {
        MiniAppDefinition(id: id, title: title, systemImage: "rectangle.on.rectangle") { _ in
            P2SceneOwnerView(owner: id)
        }
    }
}

private struct P2SceneOwnerView: View {
    let owner: MiniAppID
    /// SceneStorage supplies a value that the OS may restore for this scene. Its
    /// presence alone is not restoration evidence; the OS reconnect is observed.
    @SceneStorage private var count: Int

    init(owner: MiniAppID) {
        self.owner = owner
        _count = SceneStorage(wrappedValue: 0, owner.storageKey("p2-scene-count"))
    }

    var body: some View {
        VStack {
            Text(owner.rawValue).accessibilityIdentifier("p2.scene.owner")
            Text("\(count)").accessibilityIdentifier("p2.scene.count")
            Button("increment") { count += 1 }.accessibilityIdentifier("p2.scene.increment")
        }
    }
}

@MainActor
enum P2ScenesOSDiagnostic {
    static var connectedWindowSessions: [String] {
        UIApplication.shared.connectedScenes.compactMap { scene in
            (scene as? UIWindowScene)?.session.persistentIdentifier
        }.sorted()
    }
}
#endif
