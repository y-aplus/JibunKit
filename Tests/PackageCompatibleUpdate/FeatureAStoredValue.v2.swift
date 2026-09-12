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
