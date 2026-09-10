/// Register build requirements beside the native target's Feature dependencies.
/// Runtime MiniAppDefinition cannot change a built app's plist or entitlements.
public enum EnabledFeatureBuildRequirements {
    public static let app = FeatureBuildConfiguration(features: [
        .init(owner: "keychain-device-check", infoPlist: [
            "NSFaceIDUsageDescription": "Verify Keychain access control in this dedicated QA build.",
        ]),
    ])
    public static let widget = FeatureBuildConfiguration()
}
