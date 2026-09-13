#if os(iOS)
import Foundation
import UniformTypeIdentifiers

/// Native provider URLs expire when their callback returns. This owns copies
/// until the caller enqueues or cancels the complete selection.
public struct MiniAppPreparedIncoming: Sendable {
    public let inputs: [MiniAppIncomingStore.Input]
    public let directoryURL: URL
    public init(inputs: [MiniAppIncomingStore.Input], directoryURL: URL) {
        self.inputs = inputs
        self.directoryURL = directoryURL
    }
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
                        gate.run {
                            if let error { throw error }
                            guard let url = item as? URL, url.isFileURL else { throw MiniAppIncomingError.invalidInput }
                            try MiniAppIncomingFileAccess.copy(from: url, to: destination)
                            let type = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
                            return .file(destination, typeIdentifier: type, displayName: url.lastPathComponent)
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    progress = provider.loadObject(ofClass: NSURL.self) { item, error in
                        gate.run {
                            if let error { throw error }
                            guard let url = item as? URL, !url.isFileURL, url.scheme != nil else { throw MiniAppIncomingError.invalidInput }
                            return .url(url)
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    progress = provider.loadObject(ofClass: NSString.self) { item, error in
                        gate.run {
                            if let error { throw error }
                            guard let text = item as? String else { throw MiniAppIncomingError.invalidInput }
                            return .text(text)
                        }
                    }
                } else if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true }) {
                    let name = provider.suggestedName ?? "Shared file"
                    progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                        gate.run {
                            if let error { throw error }
                            guard let url else { throw MiniAppIncomingError.invalidInput }
                            // Source access ends at callback return. Cancellation
                            // drains this copy before the caller removes its folder.
                            try MiniAppIncomingFileAccess.copy(from: url, to: destination)
                            return .file(destination, typeIdentifier: type, displayName: name)
                        }
                    }
                } else {
                    gate.run { throw MiniAppIncomingError.invalidInput }
                    return
                }
                gate.setProgress(progress)
            }
        } onCancel: { gate.cancel() }
    }
}

/// Cancellation resumes immediately if no callback is running, including a
/// provider that never replies. An already running copy is drained first, so
/// caller cleanup cannot race it. Duplicate and late callbacks never do work.
final class ProviderContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<MiniAppIncomingStore.Input, Error>?
    private var progress: Progress?
    private var finished = false
    private var running = false
    private var cancelled = false

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
        let shouldCancel = cancelled
        if !finished { progress = value }
        lock.unlock()
        if shouldCancel { value.cancel() }
    }

    func run(_ operation: () throws -> MiniAppIncomingStore.Input) {
        lock.lock()
        guard !finished, !running else { lock.unlock(); return }
        running = true
        lock.unlock()
        let result = Result { try operation() }
        lock.lock()
        running = false
        finished = true
        let pending = continuation
        continuation = nil
        progress = nil
        let finalResult = cancelled ? .failure(CancellationError()) : result
        lock.unlock()
        pending?.resume(with: finalResult)
    }

    func cancel() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        cancelled = true
        let pendingProgress = progress
        progress = nil
        let pending = running ? nil : continuation
        if !running {
            finished = true
            continuation = nil
        }
        lock.unlock()
        pending?.resume(throwing: CancellationError())
        pendingProgress?.cancel()
    }
}
#endif
