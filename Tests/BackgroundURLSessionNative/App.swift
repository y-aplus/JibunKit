import Foundation
import JibunKitCore
import SwiftUI

@main
struct BackgroundURLSessionNativeApp: App {
    var body: some Scene {
        WindowGroup { BackgroundURLSessionProbeView() }
    }
}

private struct BackgroundURLSessionProbeView: View {
    @State private var result = "ready"

    var body: some View {
        VStack {
            Text(result)
                .accessibilityIdentifier("background-urlsession.result")
            Button("Run native background downloads") {
                result = "running"
                Task {
                    do {
                        result = try await BackgroundURLSessionProbe.run()
                    } catch {
                        result = "failed: \(error)"
                    }
                }
            }
            .accessibilityIdentifier("background-urlsession.run")
        }
    }
}

@MainActor
private enum BackgroundURLSessionProbe {
    enum Failure: Error {
        case missingServer, invalidResponse, wrongOwner(String), expectedCancellation
    }

    static func run() async throws -> String {
        guard let rawBaseURL = ProcessInfo.processInfo.environment["BACKGROUND_URLSESSION_BASE_URL"],
              let baseURL = URL(string: rawBaseURL)
        else { throw Failure.missingServer }

        let runID = UUID().uuidString
        let a = try BackgroundDownloadOwner(
            context: context("background-download-a"), profile: "primary", runID: runID)
        let b = try BackgroundDownloadOwner(
            context: context("background-download-b"), profile: "primary", runID: runID)
        defer {
            a.invalidate()
            b.invalidate()
        }

        let aFirst = a.start(request: request(baseURL: baseURL, path: "owner-a", owner: "owner-a"))
        let bFirst = b.start(request: request(baseURL: baseURL, path: "owner-b", owner: "owner-b"))
        let aFirstURL = try await a.result(for: aFirst)
        let bFirstURL = try await b.result(for: bFirst)
        try verify(aFirstURL, owner: "owner-a", directory: a.destinationDirectory)
        try verify(bFirstURL, owner: "owner-b", directory: b.destinationDirectory)

        let gate = UUID().uuidString
        let held = a.start(request: request(baseURL: baseURL, path: "hold/\(gate)", owner: "owner-a"))
        let (_, startedResponse) = try await URLSession.shared.data(
            from: baseURL.appending(path: "await-start/\(gate)"))
        guard (startedResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure.invalidResponse
        }
        let bSurvivor = b.start(
            request: request(baseURL: baseURL, path: "owner-b-survivor", owner: "owner-b"))
        held.cancel()
        _ = try await URLSession.shared.data(from: baseURL.appending(path: "release/\(gate)"))

        do {
            _ = try await a.result(for: held)
            throw Failure.expectedCancellation
        } catch let error as URLError where error.code == .cancelled {
            // Native cancellation is scoped to A's task.
        }
        let bSurvivorURL = try await b.result(for: bSurvivor)
        try verify(bSurvivorURL, owner: "owner-b", directory: b.destinationDirectory)

        guard a.completedTaskCount == 1, a.cancelledTaskCount == 1,
              b.completedTaskCount == 2, b.cancelledTaskCount == 0
        else { throw Failure.invalidResponse }
        return "passed: a-destination=owner-a b-destination=owner-b a-cancelled b-continued native-downloads=3"
    }

    private static func context(_ id: String) -> MiniAppContext {
        MiniAppContext(id: MiniAppID(id))
    }

    private static func request(baseURL: URL, path: String, owner: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue(owner, forHTTPHeaderField: "X-Fixture-Owner")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private static func verify(_ url: URL, owner: String, directory: URL) throws {
        guard url.deletingLastPathComponent() == directory else {
            throw Failure.wrongOwner("destination")
        }
        let value = try String(contentsOf: url, encoding: .utf8)
        guard value == owner else { throw Failure.wrongOwner(value) }
    }
}

@MainActor
private final class BackgroundDownloadOwner: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private struct Pending {
        let continuation: CheckedContinuation<URL, Error>
    }

    let destinationDirectory: URL
    private var session: URLSession!
    private var pending: [Int: Pending] = [:]
    private var completed: [Int: Result<URL, Error>] = [:]
    private(set) var completedTaskCount = 0
    private(set) var cancelledTaskCount = 0

    init(context: MiniAppContext, profile: String, runID: String) throws {
        let identifier = try context.backgroundURLSessionIdentifier(profile: profile)
        destinationDirectory = FileManager.default.temporaryDirectory
            .appending(path: runID, directoryHint: .isDirectory)
            .appending(path: context.id.storageNamespace, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func start(request: URLRequest) -> URLSessionDownloadTask {
        let task = session.downloadTask(with: request)
        task.resume()
        return task
    }

    func result(for task: URLSessionDownloadTask) async throws -> URL {
        if let result = completed.removeValue(forKey: task.taskIdentifier) {
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[task.taskIdentifier] = Pending(continuation: continuation)
        }
    }

    func invalidate() { session.invalidateAndCancel() }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let destination = destinationDirectory.appending(
            path: "\(downloadTask.taskIdentifier).download")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            Task { @MainActor in complete(downloadTask.taskIdentifier, result: .failure(error)) }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task { @MainActor in
            if let error {
                if (error as? URLError)?.code == .cancelled { cancelledTaskCount += 1 }
                complete(task.taskIdentifier, result: .failure(error))
            } else {
                completedTaskCount += 1
                complete(
                    task.taskIdentifier,
                    result: .success(destinationDirectory.appending(
                        path: "\(task.taskIdentifier).download"))
                )
            }
        }
    }

    private func complete(_ taskID: Int, result: Result<URL, Error>) {
        if let pending = pending.removeValue(forKey: taskID) {
            pending.continuation.resume(with: result)
        } else {
            completed[taskID] = result
        }
    }
}
