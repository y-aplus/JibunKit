public enum SDKInfo {
    public static let version = "vendor-b-2.0"
}

@MainActor
public final class SDKConfiguration {
    public static let shared = SDKConfiguration()
    public var value = "vendor-b-default"

    private init() {}
}
