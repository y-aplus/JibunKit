import Foundation

/// Text the host shows for this Feature, in the device language.
public enum BuilderText {
    public static var title: String { localized("Build") }
    /// The package's string tables, for text written in the integration.
    public static var bundle: Bundle { .module }

    /// Looks up `key` (the English text, with `%@` or `%lld` for arguments).
    /// Unlike `String(localized:)`, this also works in the Linux tests.
    static func localized(_ key: String, _ arguments: CVarArg...) -> String {
        let format = Bundle.module.localizedString(forKey: key, value: key, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: .current, arguments: arguments)
    }
}
