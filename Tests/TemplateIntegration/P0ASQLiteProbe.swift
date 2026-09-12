// Copied only into the isolated signed CI host, never into a distributed IPA.
#if os(iOS)
import Foundation
import JibunKitCore
import Observation
import SQLite3
import SwiftUI

@MainActor
enum P0ASQLiteProbe {
    static let definition = MiniAppDefinition(
        id: MiniAppID("p0a-sqlite"),
        title: "P0-A SQLite",
        systemImage: "cylinder.split.1x2"
    ) { _ in
        P0ASQLiteProbeView()
    }
}

private struct P0ASQLiteProbeView: View {
    @State private var state = P0ASQLiteProbeState()

    var body: some View {
        VStack(spacing: 16) {
            Text(state.result)
                .accessibilityIdentifier("p0a.sqlite.result")
            Button("Run native SQLite ownership comparison") { state.run() }
                .disabled(state.isRunning)
                .accessibilityIdentifier("p0a.sqlite.run")
        }
        .padding()
        .navigationTitle("P0-A SQLite")
    }
}

@MainActor
@Observable
private final class P0ASQLiteProbeState {
    var result = "idle"
    var isRunning = false

    private let coordinator = MiniAppRestoreCoordinator()
    private let ownerA = MiniAppID("p0a-sqlite-a")
    private let ownerB = MiniAppID("p0a-sqlite-b")
    private var runtimeA: MiniAppRuntime?
    private var runtimeB: MiniAppRuntime?
    private var storeA: P0ANativeSQLiteStore?
    private var storeB: P0ANativeSQLiteStore?

    func run() {
        guard !isRunning else { return }
        isRunning = true
        result = "running"
        Task {
            do {
                let value = try await executeComparison()
                try await shutdownAll()
                result = value
                print("P0A_SQLITE \(value)")
            } catch {
                try? await shutdownAll()
                result = "failed: \(error)"
            }
            isRunning = false
        }
    }

    private func executeComparison() async throws -> String {
        let filesA = try MiniAppFiles.shared(context: MiniAppContext(id: ownerA))
        let filesB = try MiniAppFiles.shared(context: MiniAppContext(id: ownerB))
        let a = P0ANativeSQLiteStore(url: try filesA.fileURL(named: "p0a.sqlite"))
        let b = P0ANativeSQLiteStore(url: try filesB.fileURL(named: "p0a.sqlite"))
        storeA = a
        storeB = b
        try await a.recreate(value: 10)
        try await b.recreate(value: 20)
        try await startRuntimeA()
        try await startRuntimeB()

        try await coordinator.withStoreAccess(for: ownerA) { try await a.write(11) }
        try await coordinator.withStoreAccess(for: ownerB) { try await b.write(22) }
        let normalA = try await a.value()
        let normalB = try await b.value()

        let lifecycle = MiniAppRestoreLifecycle(
            stop: { try await self.stopRuntimeA() },
            resume: { try await self.startRuntimeA() })
        let migrated = try await coordinator.withStoreMaintenance(for: ownerA, lifecycle: lifecycle) {
            try await a.migrate(value: 31)
        }
        let migratedLabel = try await a.hasLabelColumn()
        let migratedB = try await b.value()

        do {
            try await coordinator.withStoreMaintenance(for: ownerA, lifecycle: lifecycle) {
                try await a.failAndRollBack(value: 99)
            }
            throw P0ASQLiteProbeError.expectedFailureMissing
        } catch P0ASQLiteProbeError.intentionalFailure {
            // The store rolled back before returning the expected error.
        }
        let rolledBackA = try await a.value()
        let rolledBackLabel = try await a.hasLabelColumn()
        let rolledBackB = try await b.value()

        try await coordinator.withStoreMaintenance(for: ownerA, lifecycle: lifecycle) {
            try await a.reset()
        }
        let resetA = try await a.value()
        let resetLabel = try await a.hasLabelColumn()
        let resetB = try await b.value()

        return "normal a=\(normalA) b=\(normalB); migrated a=\(migrated) label=\(migratedLabel) b=\(migratedB); rollback a=\(rolledBackA) label=\(rolledBackLabel) b=\(rolledBackB); reset a=\(resetA) label=\(resetLabel) b=\(resetB)"
    }

    private func startRuntimeA() async throws {
        guard let storeA else { throw P0ASQLiteProbeError.missingStore }
        try await storeA.requireClosed()
        try await storeA.open()
        let runtime = MiniAppRuntime()
        try runtime.onShutdownAsync { try? await storeA.close() }
        runtimeA = runtime
    }

    private func startRuntimeB() async throws {
        guard let storeB else { throw P0ASQLiteProbeError.missingStore }
        try await storeB.requireClosed()
        try await storeB.open()
        let runtime = MiniAppRuntime()
        try runtime.onShutdownAsync { try? await storeB.close() }
        runtimeB = runtime
    }

    private func stopRuntimeA() async throws {
        guard let runtimeA else { throw P0ASQLiteProbeError.missingRuntime }
        await runtimeA.shutdown()
        // Runtime cleanup is nonthrowing. Do not treat a rejected native close
        // as a completed connection boundary before opening a maintenance handle.
        try await storeA?.requireClosed()
        self.runtimeA = nil
    }

    private func shutdownAll() async throws {
        if let runtimeA { await runtimeA.shutdown() }
        if let runtimeB { await runtimeB.shutdown() }
        runtimeA = nil
        runtimeB = nil
        // Also dispose partially initialized stores if setup failed before a
        // runtime was registered. Both owners get a cleanup attempt.
        try? await storeA?.close()
        try? await storeB?.close()
        try await storeA?.requireClosed()
        try await storeB?.requireClosed()
    }
}

private enum P0ASQLiteProbeError: Error {
    case missingStore
    case missingRuntime
    case intentionalFailure
    case expectedFailureMissing
    case connectionStillOpen
}

/// Owns one native connection and all synchronous SQL on its actor executor.
/// Runtime cleanup closes the live connection; maintenance owns its scoped one.
private actor P0ANativeSQLiteStore {
    private let url: URL
    private var handle: OpaquePointer?

    init(url: URL) { self.url = url }

    func recreate(value: Int) throws {
        try close()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
        try open()
        try exec("CREATE TABLE entry(value INTEGER); INSERT INTO entry VALUES(\(value))")
        try close()
    }

    func open() throws {
        guard handle == nil else { return }
        var opened: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard status == SQLITE_OK else {
            sqlite3_close_v2(opened)
            throw error(status)
        }
        handle = opened
    }

    func close() throws {
        guard let handle else { return }
        let status = sqlite3_close(handle)
        guard status == SQLITE_OK else { throw error(status) }
        self.handle = nil
    }

    func requireClosed() throws {
        guard handle == nil else { throw P0ASQLiteProbeError.connectionStillOpen }
    }

    func write(_ value: Int) throws { try exec("UPDATE entry SET value=\(value)") }
    func value() throws -> Int { try scalar("SELECT value FROM entry") }
    func hasLabelColumn() throws -> Int {
        try scalar("SELECT count(*) FROM pragma_table_info('entry') WHERE name='label'")
    }

    func migrate(value: Int) throws -> Int {
        try requireClosed()
        try open()
        defer { try? close() }
        try transaction {
            try exec("ALTER TABLE entry ADD COLUMN label TEXT")
            try exec("UPDATE entry SET value=\(value), label='migrated'")
        }
        return try scalar("SELECT value FROM entry WHERE label='migrated'")
    }

    func failAndRollBack(value: Int) throws {
        try requireClosed()
        try open()
        defer { try? close() }
        do {
            try transaction {
                try exec("UPDATE entry SET value=\(value)")
                throw P0ASQLiteProbeError.intentionalFailure
            }
        } catch P0ASQLiteProbeError.intentionalFailure {
            throw P0ASQLiteProbeError.intentionalFailure
        }
    }

    func reset() throws {
        try requireClosed()
        try open()
        defer { try? close() }
        try transaction {
            try exec("DROP TABLE entry")
            try exec("CREATE TABLE entry(value INTEGER)")
            try exec("INSERT INTO entry VALUES(0)")
        }
    }

    private func transaction(_ operation: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            try operation()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func exec(_ sql: String) throws {
        guard let handle else { throw P0ASQLiteProbeError.missingStore }
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw error(status) }
    }

    private func scalar(_ sql: String) throws -> Int {
        guard let handle else { throw P0ASQLiteProbeError.missingStore }
        var statement: OpaquePointer?
        let prepare = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepare == SQLITE_OK, let statement else { throw error(prepare) }
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW else { throw error(step) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func error(_ status: Int32) -> NSError {
        NSError(domain: "P0ASQLiteProbe", code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite status \(status)"
        ])
    }
}
#endif
