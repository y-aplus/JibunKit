import Foundation
import ResourceFeatureA
import ResourceFeatureB

enum VerificationFailure: Error { case resourceValues }

if CommandLine.arguments.count != 2 { throw VerificationFailure.resourceValues }
let store = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
try encoder.encode(FeatureAStoredValue(name: "alpha"))
    .write(to: store.appendingPathComponent("feature-a.json"), options: .atomic)
try encoder.encode(FeatureBStoredValue(count: 7))
    .write(to: store.appendingPathComponent("feature-b.json"), options: .atomic)

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
try verifyResources()
print("v1 seeded A/B values and verified package-owned resources")
