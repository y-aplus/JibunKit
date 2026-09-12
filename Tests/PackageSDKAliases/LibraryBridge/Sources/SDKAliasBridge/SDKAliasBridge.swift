import FeatureA
import FeatureB

public struct SDKAliasSnapshot: Equatable, Sendable {
    public let aVersion: String
    public let bVersion: String
    public let aConfiguration: String
    public let bConfiguration: String
}

@MainActor
public enum SDKAliasBridge {
    public static func snapshot() -> SDKAliasSnapshot {
        SDKAliasSnapshot(
            aVersion: FeatureAClient.sdkVersion,
            bVersion: FeatureBClient.sdkVersion,
            aConfiguration: FeatureAClient.configuration,
            bConfiguration: FeatureBClient.configuration
        )
    }

    public static func writeA(_ value: String) {
        FeatureAClient.configuration = value
    }

    public static func writeB(_ value: String) {
        FeatureBClient.configuration = value
    }
}
