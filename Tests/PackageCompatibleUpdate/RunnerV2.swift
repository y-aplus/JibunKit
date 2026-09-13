import Foundation
import ResourceFeatureA
import ResourceFeatureB

enum VerificationFailure: Error {
    case invalidArguments
    case oldAValue
    case updatedAValue
    case changedBValue
    case corruptAWasAccepted
    case corruptAWasModified
    case resourceValues
}

func verifyResources() throws {
    let aOwner = try ResourceFeatureAValues.jsonOwner()
    let bOwner = try ResourceFeatureBValues.jsonOwner()
    guard aOwner == "A",
          ResourceFeatureAValues.explicitGreeting(locale: "en") == "Hello from A",
          ResourceFeatureAValues.explicitGreeting(locale: "fr") == "Bonjour de A",
          ResourceFeatureAValues.explicitGreeting(locale: "ja") == "Aからこんにちは",
          bOwner == "B",
          ResourceFeatureBValues.explicitGreeting(locale: "en") == "Hello from B",
          ResourceFeatureBValues.explicitGreeting(locale: "fr") == "Bonjour de B",
          ResourceFeatureBValues.explicitGreeting(locale: "ja") == "Bからこんにちは"
    else { throw VerificationFailure.resourceValues }
}

func main() throws {
    guard CommandLine.arguments.count == 3 else { throw VerificationFailure.invalidArguments }
    let operation = CommandLine.arguments[1]
    let store = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let aURL = store.appendingPathComponent("feature-a.json")
    let bURL = store.appendingPathComponent("feature-b.json")
    let bBaselineURL = store.appendingPathComponent("feature-b.baseline.json")
    let decoder = JSONDecoder()

    switch operation {
    case "update":
        let oldA = try decoder.decode(FeatureAStoredValue.self, from: Data(contentsOf: aURL))
        guard oldA == FeatureAStoredValue(name: "alpha", note: nil, priority: 0)
        else { throw VerificationFailure.oldAValue }
        let updated = FeatureAStoredValue(name: oldA.name, note: "added by v2", priority: 2)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(updated).write(to: aURL, options: .atomic)
        guard try decoder.decode(FeatureAStoredValue.self, from: Data(contentsOf: aURL)) == updated
        else { throw VerificationFailure.updatedAValue }
        guard try Data(contentsOf: bURL) == Data(contentsOf: bBaselineURL)
        else { throw VerificationFailure.changedBValue }
        try verifyResources()
        print("v2 read v1 A defaults, saved/re-read new fields, and preserved B/resources")
    case "reject-corrupt":
        let corruptBytes = try Data(contentsOf: aURL)
        do {
            _ = try decoder.decode(FeatureAStoredValue.self, from: corruptBytes)
            throw VerificationFailure.corruptAWasAccepted
        } catch VerificationFailure.corruptAWasAccepted {
            throw VerificationFailure.corruptAWasAccepted
        } catch {
            guard try Data(contentsOf: aURL) == corruptBytes
            else { throw VerificationFailure.corruptAWasModified }
            guard try Data(contentsOf: bURL) == Data(contentsOf: bBaselineURL)
            else { throw VerificationFailure.changedBValue }
            try verifyResources()
            print("v2 rejected corrupt A bytes without replacing them; B/resources remain intact")
        }
    default:
        throw VerificationFailure.invalidArguments
    }
}

try main()
