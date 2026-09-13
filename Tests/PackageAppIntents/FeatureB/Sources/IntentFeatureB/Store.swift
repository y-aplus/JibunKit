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
        try Task.checkCancellation()
        return try await operation()
    }
}

@MainActor
public final class FeatureBStore {
    public enum Failure: Error, Equatable { case injectedSaveFailure, valueOutOfRange }
    public static let shared = FeatureBStore()
    private let defaults: UserDefaults
    private var boundary: any StoreOperationBoundary = DirectStoreOperationBoundary()
    private var failNextSave = false
    private var nextSaveDelayNanoseconds: UInt64 = 0

    public init(defaults: UserDefaults = UserDefaults(suiteName: "com.jibunkit.intent-fixture.b")!) {
        self.defaults = defaults
    }
    public func configure(boundary: any StoreOperationBoundary) { self.boundary = boundary }
    public func injectNextSaveFailure() { failNextSave = true }
    public func delayNextSave(nanoseconds: UInt64) { nextSaveDelayNanoseconds = nanoseconds }
    public func value() async throws -> Int {
        let defaults = defaults
        return try await boundary.perform { defaults.integer(forKey: "value") }
    }
    public func add(_ amount: Int) async throws -> Int {
        let defaults = defaults
        let shouldFail = failNextSave
        let delay = nextSaveDelayNanoseconds
        failNextSave = false
        nextSaveDelayNanoseconds = 0
        try Task.checkCancellation()
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        try Task.checkCancellation()
        return try await boundary.perform {
            try Task.checkCancellation()
            let oldValue = defaults.integer(forKey: "value")
            let (newValue, overflow) = oldValue.addingReportingOverflow(amount)
            guard !overflow else { throw Failure.valueOutOfRange }
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
    public func removeAllReserved() {
        defaults.removeObject(forKey: "value")
        defaults.removeObject(forKey: "entry-titles")
    }
}
