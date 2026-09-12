public enum SDKInfo {
    public static let version = "vendor-a-1.0"
}

@MainActor
public final class SDKConfiguration {
    public static let shared = SDKConfiguration()
    public var value = "vendor-a-default"

    private init() {}
}
