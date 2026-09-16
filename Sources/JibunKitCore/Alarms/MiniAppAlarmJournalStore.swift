import Foundation

#if os(iOS) || os(macOS)
public struct MiniAppAlarmJournalStore: MiniAppAlarmRegistrationStore {
    private let journal: MiniAppContinuingJournal

    public init(journal: MiniAppContinuingJournal) { self.journal = journal }

    public func read() throws -> [MiniAppContinuingRegistration] { try journal.read() }

    public func write(_ registrations: [MiniAppContinuingRegistration]) throws {
        try journal.update { $0 = registrations }
    }
}
#endif
