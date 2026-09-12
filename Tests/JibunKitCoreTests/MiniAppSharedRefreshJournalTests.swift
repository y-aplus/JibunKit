import Foundation
import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppSharedRefreshJournalTests: XCTestCase {
    func testRoundTripPreservesOrderEveryPhaseAndIndependentLogicalRequests() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let date = Date(timeIntervalSinceReferenceDate: 123_456)
        let records = [
            record(owner: "feature-a", id: "shared", generation: 1,
                   date: date, phase: .running),
            record(owner: "feature-a", id: "shared", generation: 2,
                   date: date.addingTimeInterval(60), phase: .pending),
            record(owner: "feature-b", id: "shared", generation: 3,
                   date: nil, phase: .pending),
            record(owner: "feature-c", id: "recover", generation: 4,
                   date: date.addingTimeInterval(-60), phase: .recovery),
            record(owner: "feature-c", id: "recover", generation: 5,
                   date: date.addingTimeInterval(120), phase: .pending),
        ]

        let journal = try FileSharedRefreshJournal(url: fixture.journalURL)
        try journal.save(records)

        XCTAssertEqual(try journal.load(), records)
    }

    func testMissingJournalLoadsAsEmptyAndFirstSaveCreatesParents() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let journal = try FileSharedRefreshJournal(url: fixture.journalURL)

        XCTAssertEqual(try journal.load(), [])
        try journal.save([record(owner: "a", id: "one", generation: 1)])
        XCTAssertEqual(try journal.load().map(\.identifier), ["one"])
    }

    func testCorruptEmptyAndUnsupportedJournalThrowWithoutChangingBytes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.journalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let journal = try FileSharedRefreshJournal(url: fixture.journalURL)
        let payloads = [
            Data(),
            Data("not json".utf8),
            Data(#"{"version":1,"records":[{"owner":"a","identifier":"id","generation":"00000000-0000-0000-0000-000000000001","earliestBeginDate":1e999,"phase":"pending"}]}"#.utf8),
            Data(#"{"version":1,"records":[{"owner":"a","identifier":"id","generation":"00000000-0000-0000-0000-000000000001","phase":"unknown"}]}"#.utf8),
            try JSONSerialization.data(withJSONObject: ["version": 2, "records": []]),
        ]

        for payload in payloads {
            try payload.write(to: fixture.journalURL)
            XCTAssertThrowsError(try journal.load())
            XCTAssertEqual(try Data(contentsOf: fixture.journalURL), payload)
        }
    }

    func testInvalidDecodedRecordsThrowWithoutChangingBytes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.journalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let journal = try FileSharedRefreshJournal(url: fixture.journalURL)
        let generation = uuid(1).uuidString
        let invalidObjects: [[String: Any]] = [
            ["version": 1, "records": [[
                "owner": "", "identifier": "id", "generation": generation,
                "phase": "pending",
            ]]],
            ["version": 1, "records": [[
                "owner": "a", "identifier": "", "generation": generation,
                "phase": "pending",
            ]]],
            ["version": 1, "records": [
                ["owner": "a", "identifier": "one", "generation": generation,
                 "phase": "running"],
                ["owner": "b", "identifier": "two", "generation": generation,
                 "phase": "recovery"],
            ]],
            ["version": 1, "records": [
                ["owner": "a", "identifier": "one", "generation": uuid(1).uuidString,
                 "phase": "pending"],
                ["owner": "a", "identifier": "one", "generation": uuid(2).uuidString,
                 "phase": "pending"],
            ]],
        ]

        for object in invalidObjects {
            let payload = try JSONSerialization.data(withJSONObject: object)
            try payload.write(to: fixture.journalURL)
            XCTAssertThrowsError(try journal.load())
            XCTAssertEqual(try Data(contentsOf: fixture.journalURL), payload)
        }
    }

    func testInvalidSaveLeavesExistingJournalBytesUnchanged() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let journal = try FileSharedRefreshJournal(url: fixture.journalURL)
        try journal.save([record(owner: "a", id: "valid", generation: 1)])
        let original = try Data(contentsOf: fixture.journalURL)
        let invalidDates = [Date(timeIntervalSinceReferenceDate: .infinity),
                            Date(timeIntervalSinceReferenceDate: .nan)]
        let invalidSets = [
            [record(owner: "", id: "id", generation: 2)],
            [record(owner: "a", id: "", generation: 2)],
            [record(owner: "a", id: "one", generation: 2),
             record(owner: "b", id: "two", generation: 2)],
            [record(owner: "a", id: "same", generation: 2),
             record(owner: "a", id: "same", generation: 3)],
        ] + invalidDates.map {
            [record(owner: "a", id: "date", generation: 2, date: $0)]
        }

        for records in invalidSets {
            XCTAssertThrowsError(try journal.save(records))
            XCTAssertEqual(try Data(contentsOf: fixture.journalURL), original)
        }
    }

    func testSaveFailureThrowsAndNonFileURLIsRejected() throws {
        XCTAssertThrowsError(try FileSharedRefreshJournal(
            url: URL(string: "https://example.com/journal.json")!
        ))

        let fixture = try Fixture()
        defer { fixture.remove() }
        let blockingParent = fixture.root.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: blockingParent)
        let journal = try FileSharedRefreshJournal(
            url: blockingParent.appendingPathComponent("journal.json")
        )

        // On macOS, traversing through a file is a read failure, not the
        // explicit no-such-file Cocoa error accepted as an empty journal.
        XCTAssertThrowsError(try journal.load())
        XCTAssertThrowsError(try journal.save([
            record(owner: "a", id: "one", generation: 1),
        ]))
        XCTAssertEqual(try Data(contentsOf: blockingParent), Data("occupied".utf8))
    }

    private func record(
        owner: String,
        id: String,
        generation: Int,
        date: Date? = nil,
        phase: MiniAppSharedRefreshRecord.Phase = .pending
    ) -> MiniAppSharedRefreshRecord {
        MiniAppSharedRefreshRecord(
            owner: owner,
            identifier: id,
            generation: uuid(generation),
            earliestBeginDate: date,
            phase: phase
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private final class Fixture {
        let root: URL
        var journalURL: URL { root.appendingPathComponent("nested/shared-refresh.json") }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("shared-refresh-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
