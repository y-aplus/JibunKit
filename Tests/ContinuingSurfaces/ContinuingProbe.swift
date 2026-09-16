import AppIntents
import ContinuingFeatureA
import ContinuingFeatureB
import ContinuingAlarmFeatureA
import ContinuingAlarmFeatureB
import JibunKitCore
import SwiftUI

struct ContinuingHostIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureAIntents.self, FeatureBIntents.self, FeatureAAlarmIntents.self, FeatureBAlarmIntents.self]
    }
}

@MainActor
enum ContinuingProbe {
    static let definitions = [
        make("continuing-live-a", FeatureALiveIntegration.makeDefinition),
        make("continuing-live-b", FeatureBLiveIntegration.makeDefinition),
        make("alarm-feature-a", FeatureAAlarmIntegration.makeDefinition),
        make("alarm-feature-b", FeatureBAlarmIntegration.makeDefinition),
    ]

    private static func make(_ owner: String, _ factory: @MainActor @Sendable () throws -> MiniAppDefinition) -> MiniAppDefinition {
        do { return try factory() }
        catch {
            let reason = String(describing: error)
            return MiniAppDefinition(id: MiniAppID(owner), title: "継続活動の準備エラー",
                systemImage: "exclamationmark.triangle") { _ in Text(reason) }
        }
    }
}
