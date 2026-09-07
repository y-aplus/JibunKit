import Foundation
import XCTest
@testable import JibunKitCore

final class MiniAppBackupTests: XCTestCase {
    func testRoundTripAndSelectionLeaveUnselectedPayloadOpaque() throws {
        let first = MiniAppBackupEntry(id: MiniAppID("notes"), schemaVersion: 1, payload: Data("hello".utf8))
        let unknown = MiniAppBackupEntry(id: MiniAppID("future.app"), schemaVersion: 99, payload: Data([0, 255, 1]))
        let date = Date(timeIntervalSince1970: 123456)
        let backup = try MiniAppBackup(entries: [first, unknown], createdAt: date)
        let decoded = try MiniAppBackup.decode(backup.encoded())
        XCTAssertEqual(decoded.createdAt, date)
        XCTAssertEqual(decoded.entries, [first, unknown])
        XCTAssertEqual(try decoded.selecting([MiniAppID("notes")]), [first])
        XCTAssertEqual(try decoded.selecting([]), [])
        XCTAssertThrowsError(try decoded.selecting([MiniAppID("missing")]))
    }

    func testInvalidEnvelopeCannotYieldPartialSelection() throws {
        let entry = MiniAppBackupEntry(id: MiniAppID("notes"), schemaVersion: 1, payload: Data())
        let data = try MiniAppBackup(entries: [entry]).encoded()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for change in ["format", "version", "duplicate", "id", "schema", "payload"] {
            var object = original
            var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
            switch change {
            case "format": object["format"] = "OtherBackup"
            case "version": object["version"] = 2
            case "duplicate": entries.append(entries[0])
            case "id": entries[0]["id"] = "../notes"
            case "schema": entries[0]["schemaVersion"] = 0
            default: entries[0]["payload"] = "not base64!"
            }
            object["entries"] = entries
            XCTAssertThrowsError(try MiniAppBackup.decode(JSONSerialization.data(withJSONObject: object)), change)
        }
    }

    func testFeatureSchemaAndPayloadMustBeValidatedBeforeUse() throws {
        struct State: Codable, Equatable { let count: Int }
        let entry = MiniAppBackupEntry(id: MiniAppID("counter"), schemaVersion: 1,
                                      payload: try JSONEncoder().encode(State(count: 42)))
        XCTAssertEqual(try entry.decodePayload(State.self, supportedSchema: 1), State(count: 42))
        XCTAssertThrowsError(try entry.decodePayload(State.self, supportedSchema: 2))
        let malformed = MiniAppBackupEntry(id: MiniAppID("counter"), schemaVersion: 1,
                                          payload: Data("{\"count\":\"bad\"}".utf8))
        XCTAssertThrowsError(try malformed.decodePayload(State.self, supportedSchema: 1))
    }
}
