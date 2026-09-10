import Foundation

let arguments = CommandLine.arguments
precondition(arguments.count == 5, "bundle locale key expected-value")
guard let bundle = Bundle(path: arguments[1]),
      let path = bundle.path(
        forResource: "InfoPlist", ofType: "strings",
        inDirectory: nil, forLocalization: arguments[2]),
      let values = NSDictionary(contentsOfFile: path) as? [String: String] else {
    preconditionFailure("Unable to read localized InfoPlist.strings from native bundle")
}
precondition(values[arguments[3]] == arguments[4], "Unexpected localized value: \(values)")
print("Native bundle localized InfoPlist readback passed: \(arguments[2]) \(arguments[3])")
