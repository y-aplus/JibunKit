import Foundation
import XCTest
@testable import JibunKitCore

final class MiniAppNotificationAttachmentsTests: XCTestCase, @unchecked Sendable {
    private func container() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @MainActor
    func testNativeStyleMovePreservesSourceAndCleansOnlyPreparation() async throws {
        let root = try container()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.png")
        let bytes = Data("owned original".utf8)
        try bytes.write(to: source)
        let staging = try MiniAppNotificationAttachments(context: MiniAppContext(id: MiniAppID("a")), containerURL: root)
        let nativeDestination = root.appendingPathComponent("native-owned.png")
        let value = try await staging.withFiles(copiedFrom: [source]) { copies in
            XCTAssertEqual(try Data(contentsOf: copies[0]), bytes)
            try FileManager.default.moveItem(at: copies[0], to: nativeDestination)
            return "registered"
        }
        XCTAssertEqual(value, "registered")
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: nativeDestination), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.directoryURL.path), [])
    }

    @MainActor
    func testFailureAndCancellationCleanCopiesAndPreserveOriginal() async throws {
        let root = try container()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.png")
        try Data([1, 2, 3]).write(to: source)
        let staging = try MiniAppNotificationAttachments(context: MiniAppContext(id: MiniAppID("a")), containerURL: root)
        enum Injected: Error { case rejected }
        do {
            try await staging.withFiles(copiedFrom: [source]) { _ in throw Injected.rejected }
            XCTFail("Expected native registration failure")
        } catch Injected.rejected { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.directoryURL.path), [])
        do {
            try await staging.withFiles(copiedFrom: [source]) { _ in throw CancellationError() }
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        XCTAssertEqual(try Data(contentsOf: source), Data([1, 2, 3]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.directoryURL.path), [])
    }

    @MainActor
    func testMissingLaterSourceDiscardsPartialCopyWithoutInvokingOperation() async throws {
        let root = try container()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.png")
        try Data([4]).write(to: source)
        let staging = try MiniAppNotificationAttachments(context: MiniAppContext(id: MiniAppID("a")), containerURL: root)
        var invoked = false
        do {
            try await staging.withFiles(copiedFrom: [source, root.appendingPathComponent("missing.png")]) { _ in
                invoked = true
            }
            XCTFail("Expected missing source failure")
        } catch { XCTAssertFalse(invoked) }
        XCTAssertEqual(try Data(contentsOf: source), Data([4]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.directoryURL.path), [])
    }

    @MainActor
    func testRemovingAStagingWhileBHasActiveCopiesPreservesB() async throws {
        let root = try container()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("same.png")
        try Data([5]).write(to: source)
        let a = try MiniAppNotificationAttachments(context: MiniAppContext(id: MiniAppID("a")), containerURL: root)
        let b = try MiniAppNotificationAttachments(context: MiniAppContext(id: MiniAppID("b")), containerURL: root)
        try await b.withFiles(copiedFrom: [source]) { bFiles in
            try await a.withFiles(copiedFrom: [source, source]) { aFiles in
                XCTAssertNotEqual(aFiles[0], aFiles[1])
                XCTAssertNotEqual(aFiles[0], bFiles[0])
            }
            try a.removeStagingFiles()
            XCTAssertEqual(try Data(contentsOf: bFiles[0]), Data([5]))
        }
        XCTAssertEqual(try Data(contentsOf: source), Data([5]))
    }

    @MainActor
    func testCancellationDoesNotRemoveFilesBeforeOperationActuallyReturns() async throws {
        let root = try container()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.png")
        try Data([6]).write(to: source)
        let staging = try MiniAppNotificationAttachments(context: MiniAppContext(id: MiniAppID("a")), containerURL: root)
        var entered: CheckedContinuation<Void, Error>?
        var finish: CheckedContinuation<Void, Never>?
        var copy: URL?
        let task = Task { @MainActor in
            do {
                try await staging.withFiles(copiedFrom: [source]) { files in
                    copy = files[0]
                    await withCheckedContinuation { continuation in
                        finish = continuation
                        entered?.resume()
                        entered = nil
                    }
                    try Task.checkCancellation()
                }
            } catch {
                entered?.resume(throwing: error)
                entered = nil
                throw error
            }
        }
        // Both setup and the operation use MainActor; setup suspends before the
        // operation can publish its files. No sleeps or repeated state polling.
        try await withCheckedThrowingContinuation { entered = $0 }
        let copiedFile = try XCTUnwrap(copy)
        task.cancel()
        XCTAssertEqual(try Data(contentsOf: copiedFile), Data([6]))
        finish?.resume()
        do {
            try await task.value
            XCTFail("Expected operation cancellation")
        } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: copiedFile.path))
        XCTAssertEqual(try Data(contentsOf: source), Data([6]))
    }
}
