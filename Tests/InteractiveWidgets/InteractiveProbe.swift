import AppIntents
import InteractiveFeatureA
import InteractiveFeatureB
import JibunKitCore
import SwiftUI

struct InteractiveIntentPackages: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAIntents.self, FeatureBIntents.self] }
}

@MainActor
enum InteractiveProbe {
    static let definitions: [MiniAppDefinition] = [makeA(), makeB()]
    private static func makeA() -> MiniAppDefinition {
        do { return FeatureAMiniApp.definition(store: try .shared()) }
        catch { return unavailable(FeatureAStore.owner, error) }
    }
    private static func makeB() -> MiniAppDefinition {
        do { return FeatureBMiniApp.definition(store: try .shared()) }
        catch { return unavailable(FeatureBStore.owner, error) }
    }
    private static func unavailable(_ id: MiniAppID, _ error: Error) -> MiniAppDefinition {
        let reason = String(describing: error)
        return MiniAppDefinition(id: id, title: "操作検証の保存先エラー", systemImage: "exclamationmark.triangle") { _ in
            Text(reason)
        }
    }
}
