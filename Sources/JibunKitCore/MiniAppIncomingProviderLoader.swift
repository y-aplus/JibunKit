#if os(iOS)
import Foundation
import UniformTypeIdentifiers

/// Native provider URLs expire when their callback returns. This owns copies
/// until the caller enqueues or cancels the complete selection.
public struct MiniAppPreparedIncoming: Sendable {
    public let inputs: [MiniAppIncomingStore.Input]
    public let directoryURL: URL
    public func removeTemporaryFiles() throws {
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
    }
}

@MainActor
public enum MiniAppIncomingProviderLoader {
    public static func load(_ providers: [NSItemProvider]) async throws -> MiniAppPreparedIncoming {
        guard !providers.isEmpty else { throw MiniAppIncomingError.invalidInput }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("jibunkit-input-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: directory) } }
        var inputs: [MiniAppIncomingStore.Input] = []
        for provider in providers {
            try Task.checkCancellation()
            let file = directory.appendingPathComponent(UUID().uuidString)
            inputs.append(try await load(provider, to: file))
        }
        try Task.checkCancellation()
        complete = true
        return MiniAppPreparedIncoming(inputs: inputs, directoryURL: directory)
    }

    private static func load(_ provider: NSItemProvider, to destination: URL) async throws -> MiniAppIncomingStore.Input {
        let gate = ProviderContinuation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                let progress: Progress
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    progress = provider.loadObject(ofClass: NSURL.self) { item, error in
                        if let error { gate.finish(.failure(error)); return }
                        guard !gate.isFinished else { return }
                        do {
                            guard let url = item as? URL, url.isFileURL else { throw MiniAppIncomingError.invalidInput }
                            try MiniAppIncomingFileAccess.copy(from: url, to: destination)
                            let type = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
                            gate.finish(.success(.file(destination, typeIdentifier: type, displayName: url.lastPathComponent)))
                        } catch { gate.finish(.failure(error)) }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    progress = provider.loadObject(ofClass: NSURL.self) { item, error in
                        if let error { gate.finish(.failure(error)); return }
                        guard let url = item as? URL, !url.isFileURL, url.scheme != nil else {
                            gate.finish(.failure(MiniAppIncomingError.invalidInput)); return
                        }
                        gate.finish(.success(.url(url)))
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    progress = provider.loadObject(ofClass: NSString.self) { item, error in
                        if let error { gate.finish(.failure(error)); return }
                        if let text = item as? String { gate.finish(.success(.text(text))) }
                        else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                            gate.finish(.success(.text(text)))
                        } else { gate.finish(.failure(MiniAppIncomingError.invalidInput)) }
                    }
                } else if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true }) {
                    let name = provider.suggestedName ?? "Shared file"
                    progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                        if let error { gate.finish(.failure(error)); return }
                        guard !gate.isFinished else { return }
                        do {
                            guard let url else { throw MiniAppIncomingError.invalidInput }
                            // Deliberately synchronous inside the callback: doing
                            // this in a later Task would outlive the source URL.
                            try MiniAppIncomingFileAccess.copy(from: url, to: destination)
                            gate.finish(.success(.file(destination, typeIdentifier: type, displayName: name)))
                        } catch { gate.finish(.failure(error)) }
                    }
                } else {
                    gate.finish(.failure(MiniAppIncomingError.invalidInput))
                    return
                }
                gate.setProgress(progress)
            }
        } onCancel: { gate.cancel() }
    }
}

/// Cancellation resumes even when a provider never invokes its callback.
/// Callbacks may be synchronous, late, duplicated, or race cancellation.
private final class ProviderContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<MiniAppIncomingStore.Input, Error>?
    private var progress: Progress?
    private var finished = false

    var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return finished
    }

    func install(_ value: CheckedContinuation<MiniAppIncomingStore.Input, Error>) -> Bool {
        lock.lock()
        if finished {
            lock.unlock()
            value.resume(throwing: CancellationError())
            return false
        }
        continuation = value
        lock.unlock()
        return true
    }

    func setProgress(_ value: Progress) {
        lock.lock()
        let shouldCancel = finished
        if !finished { progress = value }
        lock.unlock()
        if shouldCancel { value.cancel() }
    }

    func finish(_ result: Result<MiniAppIncomingStore.Input, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let pending = continuation
        continuation = nil
        progress = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        let pendingProgress = progress
        lock.unlock()
        finish(.failure(CancellationError()))
        pendingProgress?.cancel()
    }
}
#endif
