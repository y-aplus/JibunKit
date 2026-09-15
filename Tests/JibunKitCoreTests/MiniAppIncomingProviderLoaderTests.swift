#if os(iOS)
import XCTest
import CoreTransferable
import UniformTypeIdentifiers
@testable import JibunKitCore

final class MiniAppIncomingProviderLoaderTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testProviderInputsEnqueueInActualHostAppGroup() async throws {
        let inbox = try MiniAppIncomingStore.shared()
        let owner = MiniAppID("native-incoming-" + UUID().uuidString.lowercased())
        let destination = MiniAppIncomingDestination(id: owner, title: "Native input", typeIdentifiers: ["public.data"])
        try inbox.setAdmission(destination, enabled: true)
        defer {
            try? inbox.setAdmission(destination, enabled: false)
            try? inbox.removeOwnedData(for: owner)
        }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { callback in
            callback(Data("Native shared text".utf8), nil)
            return nil
        }
        let prepared = try await MiniAppIncomingProviderLoader.load([
            provider, NSItemProvider(object: NSURL(string: "https://example.com/shared")!),
        ])
        defer { try? prepared.removeTemporaryFiles() }
        let receipt = try inbox.enqueue(for: owner, inputs: prepared.inputs)
        XCTAssertEqual(try MiniAppIncomingStore.shared().pending(for: owner).receipts, [receipt])
        XCTAssertEqual(receipt.items.map(\.value), ["Native shared text", "https://example.com/shared"])
    }

    @MainActor
    func testDataOnlyTextProviderDoesNotRequireNSStringConversion() async throws {
        for (type, encoding) in [(UTType.utf8PlainText, String.Encoding.utf8), (.utf16PlainText, .utf16), (.plainText, .utf8)] {
            let provider = NSItemProvider()
            let bytes = try XCTUnwrap("共有テキスト 📝".data(using: encoding))
            provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { callback in
                callback(bytes, nil)
                return nil
            }
            let result = try await MiniAppIncomingProviderLoader.load([provider])
            defer { try? result.removeTemporaryFiles() }
            guard case .text(let value)? = result.inputs.first else { return XCTFail("Missing text") }
            XCTAssertEqual(value, "共有テキスト 📝")
        }
    }

    @MainActor
    func testTransferableStringProviderKeepsExactValue() async throws {
        let expected = "共有テキスト 📝\nSecond line"
        let provider = NSItemProvider()
        provider.register(expected)
        let result = try await MiniAppIncomingProviderLoader.load([provider])
        defer { try? result.removeTemporaryFiles() }
        guard case .text(let text)? = result.inputs.first else { return XCTFail("Missing typed text") }
        XCTAssertEqual(text, expected)
    }

    @MainActor
    func testArchivedNSStringAndRawHeaderTextKeepExactValues() async throws {
        let expected = "共有テキスト 📝\nSecond line"
        let archive = try NSKeyedArchiver.archivedData(withRootObject: expected as NSString, requiringSecureCoding: true)
        for (bytes, value) in [(archive, expected), (Data("bplist00 ordinary text".utf8), "bplist00 ordinary text")] {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { callback in
                callback(bytes, nil)
                return nil
            }
            let result = try await MiniAppIncomingProviderLoader.load([provider])
            defer { try? result.removeTemporaryFiles() }
            guard case .text(let actual)? = result.inputs.first else { return XCTFail("Missing archived text") }
            XCTAssertEqual(actual, value)
        }
    }

    @MainActor
    func testNonStringAndCorruptArchivesAreRejected() async throws {
        let objects: [NSObject] = [NSNumber(value: 42), NSArray(array: ["text"]), NSDictionary(dictionary: ["text": "value"])]
        var payloads = try objects.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
        let stringArchive = try NSKeyedArchiver.archivedData(withRootObject: "value" as NSString, requiringSecureCoding: true)
        payloads.append(Data(stringArchive.prefix(25)))
        payloads.append(try PropertyListSerialization.data(fromPropertyList: ["text": "value"], format: .binary, options: 0))
        for bytes in payloads {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { callback in
                callback(bytes, nil)
                return nil
            }
            do {
                let result = try await MiniAppIncomingProviderLoader.load([provider])
                try? result.removeTemporaryFiles()
                XCTFail("Non-string or corrupt archive was accepted")
            } catch { /* An archive must securely decode to NSString, with no fallback coercion. */ }
        }
    }

    @MainActor
    func testInvalidExplicitAndGenericTextAreRejected() async {
        for type in [UTType.utf8PlainText, .utf16PlainText, .plainText] {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { callback in
                callback(Data([0xff]), nil)
                return nil
            }
            do {
                let result = try await MiniAppIncomingProviderLoader.load([provider])
                try? result.removeTemporaryFiles()
                XCTFail("Malformed text was accepted: \(type.identifier)")
            } catch { /* Failed decoding must not publish a replacement string. */ }
        }
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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
