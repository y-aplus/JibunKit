import Foundation

public enum ResourceFeatureAValues {
    public static func jsonOwner() throws -> String {
        let url = Bundle.module.url(forResource: "shared", withExtension: "json")!
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: String]
        return object["owner"]!
    }

    public static func greeting() -> String {
        Bundle.module.localizedString(forKey: "shared.greeting", value: nil, table: nil)
    }

    public static func explicitGreeting(locale: String) -> String {
        let path = Bundle.module.path(forResource: locale, ofType: "lproj")!
        return Bundle(path: path)!.localizedString(forKey: "shared.greeting", value: nil, table: nil)
    }
}
