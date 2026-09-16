#if os(iOS)
@preconcurrency import AVFoundation
import Foundation
import UIKit
@preconcurrency import VisionKit
import Vision

@MainActor
public final class MiniAppAVCapturePermissionClient: MiniAppCapturePermissionClient {
    public init() {}

    public func request(_ resource: MiniAppCaptureResource) async -> Bool {
        let mediaType: AVMediaType = resource == .camera ? .video : .audio
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }
}

public enum MiniAppAVCaptureMode: Sendable {
    case photo
    case movie
}

public enum MiniAppMovieCompletion: Sendable, Equatable {
    case succeeded(URL)
    case failed(URL, String)
}

/// Owns its entire AVFoundation graph on one actor. No AVCapture object leaves
/// the actor; photo results cross as Data and movie results as a Feature URL.
public actor MiniAppAVCaptureSessionProducer {
    private let mode: MiniAppAVCaptureMode
    private let includesAudio: Bool
    private var session: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var photoDelegates: [Int64: PhotoDelegate] = [:]
    private var movieDelegate: MovieDelegate?
    private var lastMovieCompletion: MiniAppMovieCompletion?
    private var generation: UUID?
    private var observers: [NSObjectProtocol] = []
    private var eventContinuations: [UUID: AsyncStream<MiniAppCaptureNativeEvent>.Continuation] = [:]
    private var pendingEvents: [MiniAppCaptureNativeEvent] = []
    private var startupError = RuntimeErrorBox()
    private var isStopping = false
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    public init(mode: MiniAppAVCaptureMode, includesAudio: Bool = false) {
        self.mode = mode
        self.includesAudio = includesAudio
    }

    public func start() throws {
        guard !isStopping else { throw MiniAppCaptureFailure.stopped }
        guard session == nil else { return }
        let session = AVCaptureSession()
        // Audio is process-shared and must already be configured by the injected
        // acquireAudio hook. Never create a private AVAudioSession to bypass it.
        session.usesApplicationAudioSession = true
        session.automaticallyConfiguresApplicationAudioSession = !includesAudio
        try configure(session)
        self.session = session
        startupError = RuntimeErrorBox()
        let generation = UUID()
        self.generation = generation
        installObservers(for: session, generation: generation)
        session.startRunning()
        guard session.isRunning else {
            removeObservers()
            self.session = nil
            self.generation = nil
            photoOutput = nil
            movieOutput = nil
            throw MiniAppCaptureFailure.initialization(
                startupError.read() ?? "capture session did not start"
            )
        }
    }

    private func configure(_ session: AVCaptureSession) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard let camera = AVCaptureDevice.default(for: .video) else {
            throw MiniAppCaptureFailure.unsupported
        }
        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(videoInput) else {
            throw MiniAppCaptureFailure.native("cannot add camera input")
        }
        session.addInput(videoInput)
        if includesAudio {
            guard let microphone = AVCaptureDevice.default(for: .audio) else {
                throw MiniAppCaptureFailure.unsupported
            }
            let audioInput = try AVCaptureDeviceInput(device: microphone)
            guard session.canAddInput(audioInput) else {
                throw MiniAppCaptureFailure.native("cannot add microphone input")
            }
            session.addInput(audioInput)
        }
        switch mode {
        case .photo:
            let output = AVCapturePhotoOutput()
            guard session.canAddOutput(output) else {
                throw MiniAppCaptureFailure.native("cannot add photo output")
            }
            session.addOutput(output)
            photoOutput = output
        case .movie:
            let output = AVCaptureMovieFileOutput()
            guard session.canAddOutput(output) else {
                throw MiniAppCaptureFailure.native("cannot add movie output")
            }
            session.addOutput(output)
            movieOutput = output
        }
    }

    public func stop() async {
        if isStopping {
            await withCheckedContinuation { stopWaiters.append($0) }
            return
        }
        guard let session else {
            cancelPhotos(reason: "capture stopped")
            return
        }
        isStopping = true
        defer {
            isStopping = false
            let waiters = stopWaiters
            stopWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        removeObservers()
        cancelPhotos(reason: "capture stopped")
        if let output = movieOutput, let movieDelegate {
            // Apple guarantees didFinish for every recording request, including
            // a stop immediately after startRecording.
            output.stopRecording()
            let result = await movieDelegate.completion()
            lastMovieCompletion = result
        }
        session.stopRunning()
        movieDelegate = nil
        photoOutput = nil
        movieOutput = nil
        self.session = nil
        generation = nil
        finishEventStreams()
    }

    public func capturePhoto() async throws -> Data {
        guard !isStopping, let output = photoOutput else { throw MiniAppCaptureFailure.stopped }
        return try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            let id = settings.uniqueID
            let delegate = PhotoDelegate { [weak self] data, failure in
                if let failure { continuation.resume(throwing: MiniAppCaptureFailure.native(failure)) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: MiniAppCaptureFailure.native(failure ?? "photo failed")) }
                Task { await self?.removePhotoDelegate(id) }
            }
            photoDelegates[id] = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    public func startMovie(to url: URL) throws {
        guard !isStopping, let output = movieOutput, movieDelegate == nil,
              !output.isRecording else { throw MiniAppCaptureFailure.stopped }
        lastMovieCompletion = nil
        let delegate = MovieDelegate(url: url)
        movieDelegate = delegate
        output.startRecording(to: url, recordingDelegate: delegate)
    }

    public func movieCompletion() -> MiniAppMovieCompletion? { lastMovieCompletion }

    public func events() throws -> MiniAppCaptureNativeEvents {
        guard !isStopping, let generation else { throw MiniAppCaptureFailure.stopped }
        let id = UUID()
        let pair = AsyncStream<MiniAppCaptureNativeEvent>.makeStream()
        eventContinuations[id] = pair.continuation
        pendingEvents.forEach { pair.continuation.yield($0) }
        pendingEvents.removeAll()
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeEventContinuation(id) }
        }
        return MiniAppCaptureNativeEvents(generation: generation, stream: pair.stream)
    }

    public func restartAfterInterruption() throws {
        guard !isStopping, let session else { throw MiniAppCaptureFailure.stopped }
        guard !session.isInterrupted else { throw MiniAppCaptureFailure.unavailable("capture remains interrupted") }
        if !session.isRunning { session.startRunning() }
        guard session.isRunning else { throw MiniAppCaptureFailure.native("capture session restart failed") }
    }

    private func installObservers(for session: AVCaptureSession, generation: UUID) {
        let center = NotificationCenter.default
        let startupError = self.startupError
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session,
                               queue: nil) { [weak self] note in
                let number = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber
                let reason = number.map { String($0.intValue) }
                Task { await self?.emit(.interrupted(generation: generation, reason: reason)) }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session,
                               queue: nil) { [weak self] _ in
                Task { await self?.emit(.interruptionEnded(generation: generation)) }
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session,
                               queue: nil) { [weak self] note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
                let reason = error.map { String(describing: $0) } ?? "unknown capture runtime error"
                startupError.set(reason)
                let canRestart = error?.code == .mediaServicesWereReset
                Task { await self?.emit(.runtimeFailed(generation: generation, reason: reason,
                                                       canRestart: canRestart)) }
            },
        ]
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    private func emit(_ event: MiniAppCaptureNativeEvent) {
        guard generation == event.generation else { return }
        if eventContinuations.isEmpty { pendingEvents.append(event); return }
        for continuation in eventContinuations.values { continuation.yield(event) }
    }

    private func removeEventContinuation(_ id: UUID) { eventContinuations[id] = nil }
    private func finishEventStreams() {
        eventContinuations.values.forEach { $0.finish() }
        eventContinuations.removeAll()
        pendingEvents.removeAll()
    }

    private func cancelPhotos(reason: String) {
        let delegates = Array(photoDelegates.values)
        photoDelegates.removeAll()
        delegates.forEach { $0.cancel(reason: reason) }
    }

    private func removePhotoDelegate(_ id: Int64) { photoDelegates[id] = nil }
}

/// Synchronous notification bridge containing only a lock-protected String;
/// no AVFoundation object crosses the producer actor.
private final class RuntimeErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: String?
    func set(_ value: String) { lock.withLock { reason = value } }
    func read() -> String? { lock.withLock { reason } }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let lock = NSLock()
    private var completion: (@Sendable (Data?, String?) -> Void)?
    private var processedData: Data?
    private var processingFailure: String?
    init(completion: @escaping @Sendable (Data?, String?) -> Void) { self.completion = completion }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        lock.withLock {
            processedData = photo.fileDataRepresentation()
            processingFailure = error.map { String(describing: $0) }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        let values = lock.withLock { (processedData, error.map { String(describing: $0) } ?? processingFailure) }
        finish(data: values.0, failure: values.1)
    }
    func cancel(reason: String) { finish(data: nil, failure: reason) }
    private func finish(data: Data?, failure: String?) {
        let callback = lock.withLock { () -> (@Sendable (Data?, String?) -> Void)? in
            defer { completion = nil }
            return completion
        }
        callback?(data, failure)
    }
}

/// Delegate callbacks may arrive on an arbitrary queue. Only immutable URL and
/// lock-protected value/continuations cross that boundary; no AVCapture object
/// is stored or declared Sendable here.
private final class MovieDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var result: MiniAppMovieCompletion?
    private var waiters: [CheckedContinuation<MiniAppMovieCompletion, Never>] = []
    init(url: URL) {
        self.url = url
        super.init()
    }
    func completion() async -> MiniAppMovieCompletion {
        if let result = lock.withLock({ self.result }) { return result }
        return await withCheckedContinuation { continuation in
            let ready = lock.withLock { () -> MiniAppMovieCompletion? in
                if let result = self.result { return result }
                waiters.append(continuation)
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {}
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        let explicitlyFinished = error.map {
            ($0 as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        } ?? false
        let result: MiniAppMovieCompletion = if error == nil || explicitlyFinished {
            .succeeded(outputFileURL)
        } else if let error {
            .failed(outputFileURL, String(describing: error))
        } else {
            .failed(outputFileURL, "recording completion was unsupported")
        }
        let continuations = lock.withLock { () -> [CheckedContinuation<MiniAppMovieCompletion, Never>] in
            guard self.result == nil else { return [] }
            self.result = result
            defer { waiters.removeAll() }
            return waiters
        }
        continuations.forEach { $0.resume(returning: result) }
    }
}

@MainActor
public final class MiniAppVisionCaptureAdapter: NSObject,
    @preconcurrency VNDocumentCameraViewControllerDelegate, DataScannerViewControllerDelegate,
    UIAdaptivePresentationControllerDelegate {
    public typealias Present = @MainActor @Sendable (UIViewController) async throws -> Void
    public typealias Dismiss = @MainActor @Sendable (UIViewController) async -> Void

    @MainActor private final class Operation {
        let generation = UUID()
        let controller: UIViewController
        let documentResult: (@MainActor @Sendable (Result<[Data], Error>) -> Void)?
        let codeResult: (@MainActor @Sendable (String) -> Void)?
        let failure: (@MainActor @Sendable (MiniAppCaptureFailure) -> Void)?
        let ended: @MainActor @Sendable () async -> Void
        var handle: MiniAppPresentationOwner.Handle?
        var finishing = false
        var endingFromOwner = false

        init(controller: UIViewController,
             documentResult: (@MainActor @Sendable (Result<[Data], Error>) -> Void)? = nil,
             codeResult: (@MainActor @Sendable (String) -> Void)? = nil,
             failure: (@MainActor @Sendable (MiniAppCaptureFailure) -> Void)? = nil,
             ended: @escaping @MainActor @Sendable () async -> Void) {
            self.controller = controller
            self.documentResult = documentResult
            self.codeResult = codeResult
            self.failure = failure
            self.ended = ended
        }
    }

    private let presentationOwner: MiniAppPresentationOwner
    private let present: Present
    private let dismiss: Dismiss
    private let documentSupported: @MainActor @Sendable () -> Bool
    private let makeDocumentController: @MainActor @Sendable () -> VNDocumentCameraViewController
    private let dataScannerSupported: @MainActor @Sendable () -> Bool
    private let dataScannerAvailable: @MainActor @Sendable () -> Bool
    private let startDataScanner: @MainActor @Sendable (DataScannerViewController) throws -> Void
    private var operation: Operation?

    public init(presentationOwner: MiniAppPresentationOwner,
                present: @escaping Present, dismiss: @escaping Dismiss,
                documentSupported: @escaping @MainActor @Sendable () -> Bool = {
                    VNDocumentCameraViewController.isSupported
                },
                makeDocumentController: @escaping @MainActor @Sendable () -> VNDocumentCameraViewController = {
                    VNDocumentCameraViewController()
                },
                dataScannerSupported: @escaping @MainActor @Sendable () -> Bool = {
                    DataScannerViewController.isSupported
                },
                dataScannerAvailable: @escaping @MainActor @Sendable () -> Bool = {
                    DataScannerViewController.isAvailable
                },
                startDataScanner: @escaping @MainActor @Sendable (DataScannerViewController) throws -> Void = {
                    try $0.startScanning()
                }) {
        self.presentationOwner = presentationOwner
        self.present = present
        self.dismiss = dismiss
        self.documentSupported = documentSupported
        self.makeDocumentController = makeDocumentController
        self.dataScannerSupported = dataScannerSupported
        self.dataScannerAvailable = dataScannerAvailable
        self.startDataScanner = startDataScanner
    }

    public func documentOperation(
        result: @escaping @MainActor @Sendable (Result<[Data], Error>) -> Void,
        ended: @escaping @MainActor @Sendable () async -> Void
    ) -> MiniAppCaptureOperation {
        makeDocumentOperation(makeController: { [weak self] in
            guard let self else { throw MiniAppCaptureFailure.stopped }
            guard self.documentSupported() else { throw MiniAppCaptureFailure.unsupported }
            let controller = self.makeDocumentController()
            controller.delegate = self
            return controller
        }, result: result, ended: ended)
    }

    /// Exercises the real presentation/delegate lifetime without constructing a
    /// hardware-only VisionKit camera on an unsupported Simulator.
    @_spi(Testing)
    public func documentOperationForTesting(
        controller: UIViewController,
        result: @escaping @MainActor @Sendable (Result<[Data], Error>) -> Void,
        ended: @escaping @MainActor @Sendable () async -> Void
    ) -> MiniAppCaptureOperation {
        makeDocumentOperation(makeController: { controller }, result: result, ended: ended)
    }

    @_spi(Testing)
    public func cancelDocumentForTesting(_ controller: UIViewController) {
        cancelDocument(controller)
    }

    private func makeDocumentOperation(
        makeController: @escaping @MainActor @Sendable () throws -> UIViewController,
        result: @escaping @MainActor @Sendable (Result<[Data], Error>) -> Void,
        ended: @escaping @MainActor @Sendable () async -> Void
    ) -> MiniAppCaptureOperation {
        MiniAppCaptureOperation(resources: [.camera]) { [weak self] in
            guard let self else { throw MiniAppCaptureFailure.stopped }
            let controller = try makeController()
            let pending = Operation(controller: controller, documentResult: result, ended: ended)
            try await self.begin(pending)
            return { [weak self] _ in await self?.end(generation: pending.generation) }
        }
    }

    public func codeOperation(
        symbologies: [VNBarcodeSymbology] = [.qr],
        result: @escaping @MainActor @Sendable (String) -> Void,
        failure: @escaping @MainActor @Sendable (MiniAppCaptureFailure) -> Void = { _ in },
        ended: @escaping @MainActor @Sendable () async -> Void
    ) -> MiniAppCaptureOperation {
        MiniAppCaptureOperation(resources: [.camera]) { [weak self] in
            guard let self else { throw MiniAppCaptureFailure.stopped }
            guard self.dataScannerSupported() else { throw MiniAppCaptureFailure.unsupported }
            guard self.dataScannerAvailable() else { throw MiniAppCaptureFailure.unavailable("data scanner") }
            let controller = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: symbologies)], qualityLevel: .balanced,
                recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true
            )
            controller.delegate = self
            let pending = Operation(controller: controller, codeResult: result,
                                    failure: failure, ended: ended)
            try await self.begin(pending)
            do { try self.startDataScanner(controller) }
            catch {
                await self.end(generation: pending.generation)
                throw error
            }
            return { [weak self] _ in
                controller.stopScanning()
                await self?.end(generation: pending.generation)
            }
        }
    }

    private func begin(_ pending: Operation) async throws {
        guard operation == nil else { throw MiniAppCaptureFailure.unavailable("scanner already presented") }
        let controller = pending.controller
        let generation = pending.generation
        let handle = try presentationOwner.begin(.uiViewController) { [weak self, weak controller] in
            guard let self, let controller else { return }
            await self.dismiss(controller)
            await self.presentationDidEnd(controller: controller, generation: generation,
                                          failure: .presentationEnded)
        }
        pending.handle = handle
        operation = pending
        controller.presentationController?.delegate = self
        do {
            try await present(controller)
            controller.presentationController?.delegate = self
        }
        catch {
            presentationOwner.didEnd(handle)
            if operation === pending { operation = nil }
            throw error
        }
    }

    private func end(generation: UUID) async {
        guard let pending = operation, pending.generation == generation else { return }
        pending.finishing = true
        pending.endingFromOwner = true
        guard let handle = pending.handle else { operation = nil; return }
        await presentationOwner.end(handle)
        presentationOwner.didEnd(handle)
        if operation === pending { operation = nil }
    }

    private func finish(_ pending: Operation, action: () -> Void) {
        guard operation === pending, !pending.finishing else { return }
        pending.finishing = true
        action()
        let ended = pending.ended
        Task { @MainActor in await ended() }
    }

    private func presentationDidEnd(controller: UIViewController, generation: UUID,
                                    failure: MiniAppCaptureFailure) async {
        guard let pending = operation, pending.generation == generation,
              pending.controller === controller else { return }
        if let handle = pending.handle { presentationOwner.didEnd(handle) }
        if pending.endingFromOwner {
            if operation === pending { operation = nil }
            return
        }
        guard !pending.finishing else { return }
        pending.finishing = true
        pending.documentResult?(.failure(failure))
        pending.failure?(failure)
        operation = nil
        await pending.ended()
    }

    public func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                             didFinishWith scan: VNDocumentCameraScan) {
        guard let pending = operation, pending.controller === controller else { return }
        let pages = (0..<scan.pageCount).compactMap {
            scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.9)
        }
        finish(pending) { pending.documentResult?(.success(pages)) }
    }

    public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        cancelDocument(controller)
    }

    private func cancelDocument(_ controller: UIViewController) {
        guard let pending = operation, pending.controller === controller else { return }
        finish(pending) { pending.documentResult?(.failure(CancellationError())) }
    }

    public func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                             didFailWithError error: Error) {
        guard let pending = operation, pending.controller === controller else { return }
        finish(pending) { pending.documentResult?(.failure(error)) }
    }

    public func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        guard let pending = operation, pending.controller === dataScanner,
              case .barcode(let barcode) = item,
              let payload = barcode.payloadStringValue else { return }
        finish(pending) { pending.codeResult?(payload) }
    }

    public func dataScanner(_ dataScanner: DataScannerViewController,
                            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
        guard let pending = operation, pending.controller === dataScanner else { return }
        let failure = MiniAppCaptureFailure.unavailable(String(describing: error))
        finish(pending) { pending.failure?(failure) }
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let pending = operation,
              presentationController.presentedViewController === pending.controller else { return }
        Task { @MainActor [weak self] in
            await self?.presentationDidEnd(controller: pending.controller,
                                           generation: pending.generation,
                                           failure: .presentationEnded)
        }
    }
}
#endif
