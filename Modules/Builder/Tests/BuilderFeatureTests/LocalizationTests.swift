import Foundation
import XCTest

/// Builder localizes its own text, so it checks its tables here instead of in
/// Tools/check-localization.py.
final class LocalizationTests: XCTestCase {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func table(_ language: String) throws -> [String: String] {
        let text = try String(contentsOf: root.appendingPathComponent(
            "Sources/BuilderFeature/Resources/\(language).lproj/Localizable.strings"), encoding: .utf8)
        let entry = try NSRegularExpression(pattern: #"^"(.*)" = "(.*)";$"#, options: .anchorsMatchLines)
        var result: [String: String] = [:]
        for match in entry.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let key = String(text[Range(match.range(at: 1), in: text)!])
            XCTAssertNil(result[key], "\(language): duplicate \(key)")
            result[key] = String(text[Range(match.range(at: 2), in: text)!])
        }
        return result
    }

    func specifiers(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(@|lld)")
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range, in: text)!]) }
    }

    func testEnglishAndJapaneseMatch() throws {
        let english = try table("en"), japanese = try table("ja")
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(Set(english.keys), Set(japanese.keys))
        for (key, value) in english {
            XCTAssertEqual(value, key, "The English value must be its key")
            XCTAssertEqual(specifiers(japanese[key] ?? ""), specifiers(key), key)
        }
    }

    /// Every literal the sources look up is in the table. An interpolation in a
    /// SwiftUI or `String(localized:)` key matches any format specifier.
    func testSourcesUseOnlyTableKeys() throws {
        let keys = try table("en").keys
        let call = try NSRegularExpression(pattern:
            #"(?:BuilderText\.localized\(|String\(localized: |Text\()"((?:[^"\\]|\\.)*)"(?=[,)])"#)
        var used = 0
        for directory in ["Sources", "Integration"] {
            let files = FileManager.default.enumerator(at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil)!
            for case let file as URL in files where file.pathExtension == "swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                for match in call.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                    let literal = String(source[Range(match.range(at: 1), in: source)!])
                    let marked = literal.replacingOccurrences(of: #"\\\(.*?\)"#, with: "\u{1}", options: .regularExpression)
                    let pattern = NSRegularExpression.escapedPattern(for: marked)
                        .replacingOccurrences(of: "\u{1}", with: "%(?:@|lld)")
                    let regex = try NSRegularExpression(pattern: "^" + pattern + "$")
                    XCTAssertTrue(keys.contains { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil },
                                  "\(file.lastPathComponent): \(literal) is not in the table")
                    used += 1
                }
            }
        }
        XCTAssertGreaterThan(used, 30)
    }
}
