import Foundation

public struct FeatureAStoredValue: Codable, Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public enum FeatureACompatibleUpdate {
    public enum Failure: Error { case unsupportedStage, unexpectedEncoding }

    public static func run(stage: String, directory: URL) throws -> String {
        guard stage == "v1-seed" else { throw Failure.unsupportedStage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(FeatureAStoredValue(name: "alpha"))
        guard bytes == Data(#"{"name":"alpha"}"#.utf8) else { throw Failure.unexpectedEncoding }
        try bytes.write(to: directory.appendingPathComponent("feature-a.json"), options: .atomic)
        return "seeded-v1"
    }
}
