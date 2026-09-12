import Foundation

public struct FeatureBStoredValue: Codable, Equatable, Sendable {
    public let count: Int

    public init(count: Int) {
        self.count = count
    }
}

public enum FeatureBCompatibleUpdate {
    public enum Failure: Error { case changedBytes }

    public static func run(stage: String, directory: URL) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("feature-b.json")
        let expected = Data(#"{"count":7}"#.utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(FeatureBStoredValue(count: 7)) == expected else { throw Failure.changedBytes }
        if stage == "v1-seed" {
            try expected.write(to: url, options: .atomic)
        }
        guard try Data(contentsOf: url) == expected else { throw Failure.changedBytes }
        return expected.base64EncodedString()
    }
}
