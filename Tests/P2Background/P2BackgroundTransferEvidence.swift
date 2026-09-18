#if os(iOS)
import Foundation
import Combine
import JibunKitCore

@MainActor
final class P2BackgroundTransferEvidence: ObservableObject {
    struct Record: Codable, Equatable {
        let run: UUID
        let owner: String
        let sessionIdentifier: String
        let originProcess: UUID
        let originTaskIdentifier: Int
        let taskDescription: String
        let submittedAt: Date
        var hostCallbackProcess: UUID?
        var ownerReconnectedProcess: UUID?
        var delegateProcess: UUID?
        var delegateTaskIdentifier: Int?
        var savedSize: Int?
        var savedSHA256: String?
        var taskCompletedWithoutError = false
        var finishedEventsProcess: UUID?
        var hostCompletionReturnedProcess: UUID?
        var terminationRequestedProcess: UUID?
        var rejection: String?

        var isPending: Bool { hostCompletionReturnedProcess == nil && rejection == nil }

        var isColdRestorationEvidence: Bool {
            guard rejection == nil,
                  let callback = hostCallbackProcess,
                  callback != originProcess,
                  terminationRequestedProcess == originProcess,
                  ownerReconnectedProcess == callback,
                  delegateProcess == callback,
                  delegateTaskIdentifier == originTaskIdentifier,
                  savedSize != nil,
                  savedSHA256 != nil,
                  taskCompletedWithoutError,
                  finishedEventsProcess == callback,
                  hostCompletionReturnedProcess == callback else { return false }
            return true
        }
    }

    static let filename = "p2-background-transfer-evidence.json"
    static let taskDescriptionPrefix = "jibunkit-p2-background:"

    @Published private(set) var record: Record?
    @Published private(set) var error: String?
    private let files: MiniAppFiles
    private let owner: MiniAppID
    private let process: UUID

    init(owner: MiniAppID, files: MiniAppFiles,
         process: UUID = P2BackgroundObservationLog.processID) {
        self.owner = owner
        self.files = files
        self.process = process
        do {
            let url = try files.fileURL(named: Self.filename)
            if FileManager.default.fileExists(atPath: url.path) {
                record = try JSONDecoder().decode(Record.self, from: files.read(named: Self.filename))
            }
        } catch {
            self.error = "転送証拠読込失敗（既存ファイルを保持）: \(error)"
        }
    }

    var summary: String {
        guard let record else { return error ?? "cold復元証拠: 未開始" }
        let run = record.run.uuidString.prefix(8)
        if record.isColdRestorationEvidence {
            return "cold復元証拠: 成立 run=\(run) task=\(record.originTaskIdentifier) size=\(record.savedSize!) sha256=\(record.savedSHA256!)"
        }
        if let rejection = record.rejection { return "cold復元証拠: 不成立 run=\(run) 理由=\(rejection)" }
        return "cold復元証拠: 未成立 run=\(run) origin=\(record.originProcess.uuidString.prefix(8))"
    }

    func begin(sessionIdentifier: String, taskIdentifier: Int, run: UUID) throws -> String {
        guard record?.isPending != true else { throw Failure.pendingRun }
        let description = Self.taskDescriptionPrefix + run.uuidString.lowercased()
        record = Record(run: run, owner: owner.rawValue, sessionIdentifier: sessionIdentifier,
                        originProcess: process, originTaskIdentifier: taskIdentifier,
                        taskDescription: description, submittedAt: Date())
        try persist()
        return description
    }

    func noteHostCallback(sessionIdentifier: String) {
        guard mutateMatching(sessionIdentifier: sessionIdentifier) else { return }
        record?.hostCallbackProcess = process
        persistOrExposeError()
    }

    func noteSaved(taskDescription: String?, taskIdentifier: Int, size: Int, sha256: String) {
        guard mutateMatching(taskDescription: taskDescription, taskIdentifier: taskIdentifier) else { return }
        record?.delegateProcess = process
        record?.delegateTaskIdentifier = taskIdentifier
        record?.savedSize = size
        record?.savedSHA256 = sha256
        persistOrExposeError()
    }

    func noteOwnerReconnected() {
        guard record?.rejection == nil, record?.hostCallbackProcess == process else { return }
        record?.ownerReconnectedProcess = process
        persistOrExposeError()
    }

    func noteTaskCompletion(taskDescription: String?, taskIdentifier: Int, error: Error?) {
        guard mutateMatching(taskDescription: taskDescription, taskIdentifier: taskIdentifier) else { return }
        record?.delegateProcess = process
        record?.delegateTaskIdentifier = taskIdentifier
        record?.taskCompletedWithoutError = error == nil
        if let error { reject("task失敗: \(type(of: error))") }
        persistOrExposeError()
    }

    func noteFinishedEvents() {
        guard record?.rejection == nil else { return }
        record?.finishedEventsProcess = process
        persistOrExposeError()
    }

    func noteHostCompletionReturned() {
        guard record?.rejection == nil else { return }
        record?.hostCompletionReturnedProcess = process
        persistOrExposeError()
    }

    func canTerminateForDiagnostic(pendingTaskDescriptions: [String?]) -> Bool {
        guard let record, record.isPending,
              record.originProcess == process,
              pendingTaskDescriptions.contains(where: { $0 == record.taskDescription }) else { return false }
        return (try? files.read(named: Self.filename)).flatMap {
            try? JSONDecoder().decode(Record.self, from: $0)
        } == record
    }

    func noteTerminationRequested() {
        record?.terminationRequestedProcess = process
        persistOrExposeError()
    }

    private func mutateMatching(sessionIdentifier: String) -> Bool {
        guard let record else { return false }
        guard record.owner == owner.rawValue, record.sessionIdentifier == sessionIdentifier else {
            reject("owner/session混在"); return false
        }
        return true
    }

    private func mutateMatching(taskDescription: String?, taskIdentifier: Int) -> Bool {
        guard let record else { return false }
        guard record.owner == owner.rawValue,
              taskDescription == record.taskDescription,
              taskIdentifier == record.originTaskIdentifier else {
            reject("run/owner/task混在"); return false
        }
        return true
    }

    private func reject(_ reason: String) {
        record?.rejection = reason
        persistOrExposeError()
    }

    private func persistOrExposeError() {
        do { try persist(); error = nil }
        catch { self.error = "転送証拠保存失敗: \(error)" }
    }

    private func persist() throws {
        guard let record else { return }
        try files.write(JSONEncoder().encode(record), named: Self.filename)
    }

    enum Failure: Error { case pendingRun }
}
#endif
