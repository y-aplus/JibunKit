import XCTest
@testable import JibunKitCore

#if os(iOS) || os(macOS)
final class MiniAppIncomingFileAccessTests: XCTestCase {
    func testGrantedScopeReleasedAfterCopyAndSourceCanDisappear() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("external")
        let copy = directory.appendingPathComponent("owned")
        try Data("text".utf8).write(to: source)
        var events: [String] = []
        try MiniAppIncomingFileAccess.copy(from: source, to: copy,
            start: { _ in events.append("start"); return true },
            stop: { _ in events.append("stop"); XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path)) })
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(events, ["start", "stop"])
        XCTAssertEqual(try Data(contentsOf: copy), Data("text".utf8))
    }

    func testCopyFailureReleasesGrantedScopeWithoutReplacingDestination() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("external")
        let destination = directory.appendingPathComponent("existing")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: destination)
        var released = 0
        XCTAssertThrowsError(try MiniAppIncomingFileAccess.copy(from: source, to: destination,
            start: { _ in true }, stop: { _ in released += 1 }))
        XCTAssertEqual(released, 1)
        XCTAssertEqual(try Data(contentsOf: destination), Data("old".utf8))
    }

    func testLocalURLWithoutGrantDoesNotIssueUnbalancedStop() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source")
        try Data("local".utf8).write(to: source)
        var released = false
        try MiniAppIncomingFileAccess.copy(from: source, to: directory.appendingPathComponent("copy"),
            start: { _ in false }, stop: { _ in released = true })
        XCTAssertFalse(released)
    }
}
#endif
