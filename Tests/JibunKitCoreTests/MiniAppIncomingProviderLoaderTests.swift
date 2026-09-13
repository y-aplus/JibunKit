#if os(iOS)
import XCTest
import UniformTypeIdentifiers
@testable import JibunKitCore

@MainActor
final class MiniAppIncomingProviderLoaderTests: XCTestCase {
    func testNativeTextAndURLProvidersKeepExactValues() async throws {
        let result = try await MiniAppIncomingProviderLoader.load([
            NSItemProvider(object: "共有テキスト" as NSString),
            NSItemProvider(object: NSURL(string: "https://example.com/incoming?q=1")!),
        ])
        defer { try? result.removeTemporaryFiles() }
        XCTAssertEqual(result.inputs.count, 2)
        guard case .text(let text) = result.inputs[0], case .url(let url) = result.inputs[1] else {
            return XCTFail("Native provider representations changed")
        }
        XCTAssertEqual(text, "共有テキスト")
        XCTAssertEqual(url.absoluteString, "https://example.com/incoming?q=1")
    }

    func testNativeFileProviderReturnsOwnedCopyAndCleanupRemovesIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("bytes.bin")
        try Data([1, 2, 3, 4]).write(to: original)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.data.identifier, fileOptions: [], visibility: .all) { callback in
            callback(original, false, nil)
            return nil
        }
        let result = try await MiniAppIncomingProviderLoader.load([provider])
        try FileManager.default.removeItem(at: original)
        guard case .file(let copy, _, _) = result.inputs[0] else { return XCTFail("Missing file") }
        XCTAssertEqual(try Data(contentsOf: copy), Data([1, 2, 3, 4]))
        try result.removeTemporaryFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }

    func testCancellationBeforeRegistrationAndLateDuplicateCallbacksDoNoWork() async throws {
        let gate = ProviderContinuation()
        gate.cancel()
        do {
            let _: MiniAppIncomingStore.Input = try await withCheckedThrowingContinuation { continuation in
                XCTAssertFalse(gate.install(continuation))
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        gate.run { XCTFail("Late callback copied data"); return .text("late") }
        let progress = Progress(totalUnitCount: 1)
        gate.setProgress(progress)
        XCTAssertTrue(progress.isCancelled)
    }

    func testNativeProviderThatNeverRepliesCanBeCancelled() async {
        let entered = expectation(description: "provider requested")
        let finished = expectation(description: "loader cancelled without callback")
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.data.identifier, fileOptions: [], visibility: .all) { _ in
            entered.fulfill()
            return Progress(totalUnitCount: 1)
        }
        let task = Task { @MainActor in
            defer { finished.fulfill() }
            do {
                let result = try await MiniAppIncomingProviderLoader.load([provider])
                try? result.removeTemporaryFiles()
                XCTFail("Silent provider unexpectedly completed")
            } catch is CancellationError { }
            catch { XCTFail("Wrong failure: \(error)") }
        }
        await fulfillment(of: [entered], timeout: 5)
        task.cancel()
        await fulfillment(of: [finished], timeout: 5)
    }

    func testCancellationDrainsActiveCopyBeforeResumingAndIgnoresDuplicateCallback() async throws {
        let gate = ProviderContinuation()
        let finishedCopy = expectation(description: "copy finished")
        do {
            let _: MiniAppIncomingStore.Input = try await withCheckedThrowingContinuation { continuation in
                XCTAssertTrue(gate.install(continuation))
                DispatchQueue.global().async {
                    gate.run {
                        gate.cancel()
                        gate.run { XCTFail("Duplicate callback ran"); return .text("duplicate") }
                        finishedCopy.fulfill()
                        return .text("cancelled copy")
                    }
                }
            }
            XCTFail("Expected cancellation after copy")
        } catch is CancellationError { }
        await fulfillment(of: [finishedCopy], timeout: 0)
        gate.run { XCTFail("Late callback ran"); return .text("late") }
    }
}
#endif
