/// Register build requirements beside the native target's Feature dependencies.
/// Runtime MiniAppDefinition cannot change a built app's plist or entitlements.
public enum EnabledFeatureBuildRequirements {
    public static let app = FeatureBuildConfiguration()
    public static let widget = FeatureBuildConfiguration()
    /// Opt in only when this host includes the incoming Action Extension.
    public static let action: FeatureBuildConfiguration? = nil
    /// Opt in only when a Feature handles notifications in the host's
    /// Notification Service extension. Register its handler in
    /// `Sources/JibunKitNotificationService/NotificationService.swift`.
    public static let notificationService: FeatureBuildConfiguration? = nil
    /// Opt in only when a Feature draws notification content. List every
    /// displayed category identifier (`MiniAppContext.notificationCategoryIdentifier(for:)`).
    public static let notificationContent: (build: FeatureBuildConfiguration, categories: [String])? = nil
}
