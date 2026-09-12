import Foundation

public struct FeatureAStoredValue: Codable, Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}
