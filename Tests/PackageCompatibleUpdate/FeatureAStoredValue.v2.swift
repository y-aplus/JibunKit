import Foundation

public struct FeatureAStoredValue: Codable, Equatable, Sendable {
    public let name: String
    public let note: String?
    public let priority: Int

    public init(name: String, note: String? = nil, priority: Int = 0) {
        self.name = name
        self.note = note
        self.priority = priority
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case note
        case priority
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
    }
}

public enum FeatureACompatibleUpdate {
    public enum Failure: Error {
        case unsupportedStage
        case incompatibleOldValue
        case incompatibleUpdatedValue
        case corruptValueAccepted
        case corruptBytesChanged
    }

    public static func run(stage: String, directory: URL) throws -> String {
        let url = directory.appendingPathComponent("feature-a.json")
        let decoder = JSONDecoder()
        let expected = FeatureAStoredValue(name: "alpha", note: "added by v2", priority: 2)
        switch stage {
        case "v2-update":
            let old = try decoder.decode(FeatureAStoredValue.self, from: Data(contentsOf: url))
            guard old == FeatureAStoredValue(name: "alpha", note: nil, priority: 0)
            else { throw Failure.incompatibleOldValue }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(expected).write(to: url, options: .atomic)
            guard try decoder.decode(FeatureAStoredValue.self, from: Data(contentsOf: url)) == expected
            else { throw Failure.incompatibleUpdatedValue }
            return "old-defaults-updated"
        case "v2-relaunch":
            guard try decoder.decode(FeatureAStoredValue.self, from: Data(contentsOf: url)) == expected
            else { throw Failure.incompatibleUpdatedValue }
            return "updated-reloaded"
        case "v2-corrupt":
            let corrupt = Data("{\"name\":".utf8)
            try corrupt.write(to: url, options: .atomic)
            do {
                _ = try decoder.decode(FeatureAStoredValue.self, from: Data(contentsOf: url))
                throw Failure.corruptValueAccepted
            } catch Failure.corruptValueAccepted {
                throw Failure.corruptValueAccepted
            } catch {
                guard try Data(contentsOf: url) == corrupt else { throw Failure.corruptBytesChanged }
                return "corrupt-rejected-preserved"
            }
        case "v2-repair":
            guard try Data(contentsOf: url) == Data("{\"name\":".utf8)
            else { throw Failure.corruptBytesChanged }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(expected).write(to: url, options: .atomic)
            guard try decoder.decode(FeatureAStoredValue.self, from: Data(contentsOf: url)) == expected
            else { throw Failure.incompatibleUpdatedValue }
            return "repaired-reloaded"
        default:
            throw Failure.unsupportedStage
        }
    }
}
