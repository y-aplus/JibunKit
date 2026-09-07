import Foundation
import XCTest
@testable import JibunKitCore

final class MiniAppFilesTests: XCTestCase {
    private func temporaryContainer() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testFilesAreIndependentAndSurviveReopening() throws {
        let container = try temporaryContainer()
        let context = MiniAppContext(id: MiniAppID("notes"))
        let first = try MiniAppFiles(context: context, containerURL: container)
        let second = try MiniAppFiles(context: MiniAppContext(id: MiniAppID("notes.daily")), containerURL: container)
        XCTAssertNotEqual(first.directoryURL, second.directoryURL)
        try first.write(Data("first".utf8), named: "state.json")
        try second.write(Data("second".utf8), named: "state.json")
        try first.write(Data("updated".utf8), named: "state.json")
        let reopened = try MiniAppFiles(context: context, containerURL: container)
        XCTAssertEqual(try reopened.read(named: "state.json"), Data("updated".utf8))
        XCTAssertEqual(try second.read(named: "state.json"), Data("second".utf8))
    }

    func testInvalidNamesDoNotCreateDirectories() throws {
        let files = try MiniAppFiles(context: MiniAppContext(id: MiniAppID("notes")), containerURL: temporaryContainer())
        for name in ["", ".", "..", "../other", "a/b", "a\\b", "a\u{0}b", "a\nb"] {
            XCTAssertThrowsError(try files.write(Data(), named: name)) { error in
                XCTAssertEqual(error as? MiniAppFileError, .invalidFileName(name))
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.directoryURL.path))
    }

    func testMissingFileIsNotTreatedAsEmptyData() throws {
        let files = try MiniAppFiles(context: MiniAppContext(id: MiniAppID("notes")), containerURL: temporaryContainer())
        XCTAssertThrowsError(try files.read(named: "missing"))
        try files.write(Data(), named: "empty")
        XCTAssertEqual(try files.read(named: "empty"), Data())
    }

    func testSignedGroupResolutionAndUnavailableContainer() throws {
        let container = try temporaryContainer()
        let context = MiniAppContext(id: MiniAppID("notes"))
        let info: [String: Any] = ["JibunKitAppGroup": "group.example", "ALTAppGroups": ["group.example.TEAM"]]
        let files = try MiniAppFiles.shared(context: context, infoDictionary: info) { identifier in
            XCTAssertEqual(identifier, "group.example.TEAM")
            return container
        }
        XCTAssertTrue(files.directoryURL.path.hasPrefix(container.path + "/"))
        XCTAssertThrowsError(try MiniAppFiles.shared(context: context, infoDictionary: info) { _ in nil }) { error in
            XCTAssertEqual(error as? MiniAppFileError, .unavailableGroupContainer(identifier: "group.example.TEAM"))
        }
        XCTAssertThrowsError(try MiniAppFiles.shared(context: context, infoDictionary: [:]) { _ in
            XCTFail("Invalid group configuration must not resolve a fallback")
            return container
        })
    }
}
