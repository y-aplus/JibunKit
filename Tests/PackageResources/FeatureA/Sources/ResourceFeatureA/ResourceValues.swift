import Foundation

public enum ResourceFeatureAValues {
    public static func jsonOwner() throws -> String {
        let url = Bundle.module.url(forResource: "shared", withExtension: "json")!
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: String]
        return object["owner"]!
    }

    public static func greeting(locale: String) -> String {
        String(localized: "shared.greeting", bundle: .module, locale: Locale(identifier: locale))
    }
}
