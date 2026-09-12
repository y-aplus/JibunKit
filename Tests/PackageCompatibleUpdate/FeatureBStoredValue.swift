import Foundation

public struct FeatureBStoredValue: Codable, Equatable, Sendable {
    public let count: Int

    public init(count: Int) {
        self.count = count
    }
}
