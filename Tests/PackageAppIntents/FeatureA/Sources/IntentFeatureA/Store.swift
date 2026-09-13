import Foundation

public protocol StoreOperationBoundary: Sendable {
    func perform<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () throws -> Value
    ) async throws -> Value
}

public struct DirectStoreOperationBoundary: StoreOperationBoundary {
    public init() {}
    public func perform<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () throws -> Value
    ) async throws -> Value {
        try await operation()
    }
}

@MainActor
public final class FeatureAStore {
    public enum Failure: Error, Equatable { case injectedSaveFailure }

    public static let shared = FeatureAStore()
    private let defaults: UserDefaults
    private var boundary: any StoreOperationBoundary = DirectStoreOperationBoundary()
    private var failNextSave = false

    public init(defaults: UserDefaults = UserDefaults(suiteName: "com.jibunkit.intent-fixture.a")!) {
        self.defaults = defaults
    }

    public func configure(boundary: any StoreOperationBoundary) { self.boundary = boundary }
    public func injectNextSaveFailure() { failNextSave = true }

    public func value() async throws -> Int {
        let defaults = defaults
        return try await boundary.perform { defaults.integer(forKey: "value") }
    }

    public func add(_ amount: Int) async throws -> Int {
        let defaults = defaults
        let shouldFail = failNextSave
        failNextSave = false
        return try await boundary.perform {
            let oldValue = defaults.integer(forKey: "value")
            let (newValue, overflow) = oldValue.addingReportingOverflow(amount)
            guard !overflow else { throw Failure.injectedSaveFailure }
            guard !shouldFail else { throw Failure.injectedSaveFailure }
            defaults.set(newValue, forKey: "value")
            return newValue
        }
    }

    public func entries() async throws -> [String: String] {
        let defaults = defaults
        return try await boundary.perform {
            defaults.dictionary(forKey: "entry-titles") as? [String: String] ?? [:]
        }
    }

    public func replaceEntries(_ entries: [String: String]) async throws {
        let defaults = defaults
        try await boundary.perform { defaults.set(entries, forKey: "entry-titles") }
    }

    public func removeAll() async throws {
        let defaults = defaults
        try await boundary.perform {
            defaults.removeObject(forKey: "value")
            defaults.removeObject(forKey: "entry-titles")
        }
    }

    /// Used by host removal while the owner already has an exclusive reservation.
    public func removeAllReserved() {
        defaults.removeObject(forKey: "value")
        defaults.removeObject(forKey: "entry-titles")
    }
}
