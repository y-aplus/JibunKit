import Foundation

@main
struct SourceCompositionChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("A.swift.fragment")
        let b = root.appendingPathComponent("B.swift.fragment")
        let output = root.appendingPathComponent("Generated.swift")
        let sourceA = "AppShortcut(intent: A(), phrases: [\"A in \\(.applicationName)\"])"
        let sourceB = "AppShortcut(intent: B(), phrases: [\"B in \\(.applicationName)\"])"
        try sourceA.write(to: a, atomically: true, encoding: .utf8)
        try sourceB.write(to: b, atomically: true, encoding: .utf8)
        let fa = FeatureAppShortcuts(owner: "a", imports: ["FeatureA"], sourceFile: a.path)
        let fb = FeatureAppShortcuts(owner: "b", imports: ["FeatureB"], sourceFile: b.path)
        try FeatureAppShortcuts.writeProvider([fa, fb], to: output.path)
        let initial = try String(contentsOf: output, encoding: .utf8)
        precondition(initial.contains(sourceA) && initial.contains(sourceB))
        do {
            try FeatureAppShortcuts.writeProvider([fa, fa], to: output.path)
            preconditionFailure("Duplicate owner accepted")
        } catch FeatureAppShortcuts.Failure.duplicateOrEmptyOwner(_) { }
        let afterRejection = try String(contentsOf: output, encoding: .utf8)
        precondition(afterRejection == initial)
        let missing = FeatureAppShortcuts(owner: "missing", imports: [], sourceFile: root.appendingPathComponent("missing").path)
        do {
            try FeatureAppShortcuts.writeProvider([fa, missing], to: output.path)
            preconditionFailure("Missing input accepted")
        } catch { }
        let afterMissing = try String(contentsOf: output, encoding: .utf8)
        precondition(afterMissing == initial)
        try FeatureAppShortcuts.writeProvider([fb], to: output.path)
        let remaining = try String(contentsOf: output, encoding: .utf8)
        precondition(!remaining.contains(sourceA) && !remaining.contains("import FeatureA") && remaining.contains(sourceB))
        try FeatureAppShortcuts.writeProvider([], to: output.path)
        let empty = try String(contentsOf: output, encoding: .utf8)
        precondition(!empty.contains("struct JibunKitShortcuts"))
        print("Feature App Shortcuts composition: preservation, rejection, and removal passed")
    }
}
