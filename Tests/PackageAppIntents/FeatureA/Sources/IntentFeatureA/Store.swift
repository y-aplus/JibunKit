import Foundation

public protocol StoreOperationBoundary: Sendable {
    func perform<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value
}

public struct DirectStoreOperationBoundary: StoreOperationBoundary {
    public init() {}
    public func perform<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        return try await operation()
    }
}

@MainActor
public final class FeatureAStore {
    public enum Failure: Error, Equatable {
        case injectedSaveFailure
        case valueOutOfRange
    }

    public static let shared = FeatureAStore()
    private let defaults: UserDefaults
    private var boundary: any StoreOperationBoundary = DirectStoreOperationBoundary()
    // Diagnostic controls must survive reconstruction by OS AppIntent execution.
    // They use this fixture owner's existing persistent store, not UI memory.
    private static let failureKey = "diagnostic.fail-next-save"
    private static let delayKey = "diagnostic.next-save-delay"

    public init(defaults: UserDefaults = UserDefaults(suiteName: "com.jibunkit.intent-fixture.a")!) {
        self.defaults = defaults
    }

    public func configure(boundary: any StoreOperationBoundary) { self.boundary = boundary }
    public func injectNextSaveFailure() { defaults.set(true, forKey: Self.failureKey) }
    public func delayNextSave(nanoseconds: UInt64) { defaults.set(NSNumber(value: nanoseconds), forKey: Self.delayKey) }

    public func value() async throws -> Int {
        let defaults = defaults
        return try await boundary.perform { defaults.integer(forKey: "value") }
    }

    public func add(_ amount: Int) async throws -> Int {
        let defaults = defaults
        let shouldFail = defaults.bool(forKey: Self.failureKey)
        let delay = (defaults.object(forKey: Self.delayKey) as? NSNumber)?.uint64Value ?? 0
        defaults.removeObject(forKey: Self.failureKey)
        defaults.removeObject(forKey: Self.delayKey)
        try Task.checkCancellation()
        return try await boundary.perform {
            try Task.checkCancellation()
            if delay > 0 { try await Task.sleep(nanoseconds: delay) }
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
        try await boundary.perform {
            try Task.checkCancellation()
            defaults.set(entries, forKey: "entry-titles")
        }
    }

    public func removeAll() async throws {
        let defaults = defaults
        try await boundary.perform {
            try Task.checkCancellation()
            defaults.removeObject(forKey: "value")
            defaults.removeObject(forKey: "entry-titles")
            defaults.removeObject(forKey: Self.failureKey)
            defaults.removeObject(forKey: Self.delayKey)
        }
    }

    /// Used by host removal while the owner already has an exclusive reservation.
    public func removeAllReserved() {
        defaults.removeObject(forKey: "value")
        defaults.removeObject(forKey: "entry-titles")
        defaults.removeObject(forKey: Self.failureKey)
        defaults.removeObject(forKey: Self.delayKey)
    }
}
