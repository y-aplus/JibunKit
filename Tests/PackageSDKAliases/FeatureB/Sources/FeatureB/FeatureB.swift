import VendorSDK

public enum FeatureBClient {
    public static let sdkVersion = SDKInfo.version

    @MainActor
    public static var configuration: String {
        get { SDKConfiguration.shared.value }
        set { SDKConfiguration.shared.value = newValue }
    }
}
