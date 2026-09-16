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

    public init(mode: MiniAppAVCaptureMode, includesAudio: Bool = false) {
        self.mode = mode
        self.includesAudio = includesAudio
    }

    public func start() throws {
        guard session == nil else { return }
        let session = AVCaptureSession()
        // Audio is process-shared and must already be configured by the injected
        // acquireAudio hook. Never create a private AVAudioSession to bypass it.
        session.usesApplicationAudioSession = true
        session.automaticallyConfiguresApplicationAudioSession = !includesAudio
        try configure(session)
        self.session = session
        session.startRunning()
        guard session.isRunning else {
            self.session = nil
            photoOutput = nil
            movieOutput = nil
            throw MiniAppCaptureFailure.native("capture session did not start")
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
        guard let session else { return }
        if let output = movieOutput, output.isRecording {
            output.stopRecording()
            if let movieDelegate {
                for await _ in movieDelegate.finished { break }
            }
        }
        session.stopRunning()
        photoDelegates.removeAll()
        movieDelegate = nil
        photoOutput = nil
        movieOutput = nil
        self.session = nil
    }

    public func capturePhoto() async throws -> Data {
        guard let output = photoOutput else { throw MiniAppCaptureFailure.stopped }
        return try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            let id = settings.uniqueID
            let delegate = PhotoDelegate { [weak self] data, failure in
                Task {
                    await self?.removePhotoDelegate(id)
                    if let data { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: MiniAppCaptureFailure.native(failure ?? "photo failed")) }
                }
            }
            photoDelegates[id] = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    public func startMovie(to url: URL) throws {
        guard let output = movieOutput, !output.isRecording else { throw MiniAppCaptureFailure.stopped }
        let delegate = MovieDelegate()
        movieDelegate = delegate
        output.startRecording(to: url, recordingDelegate: delegate)
    }

    private func removePhotoDelegate(_ id: Int64) { photoDelegates[id] = nil }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: @Sendable (Data?, String?) -> Void
    init(completion: @escaping @Sendable (Data?, String?) -> Void) { self.completion = completion }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        completion(photo.fileDataRepresentation(), error.map { String(describing: $0) })
    }
}

private final class MovieDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    let finished: AsyncStream<String?>
    private let finishContinuation: AsyncStream<String?>.Continuation
    override init() {
        let pair = AsyncStream<String?>.makeStream()
        finished = pair.stream
        finishContinuation = pair.continuation
        super.init()
    }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {}
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        finishContinuation.yield(error.map { String(describing: $0) })
        finishContinuation.finish()
    }
}

@MainActor
public final class MiniAppVisionCaptureAdapter: NSObject,
    @preconcurrency VNDocumentCameraViewControllerDelegate, DataScannerViewControllerDelegate {
    public typealias Present = @MainActor @Sendable (UIViewController) async throws -> Void
    public typealias Dismiss = @MainActor @Sendable () async -> Void

    private let presentationOwner: MiniAppPresentationOwner
    private let present: Present
    private let dismiss: Dismiss
    private var handle: MiniAppPresentationOwner.Handle?
    private var controller: UIViewController?
    private var documentResult: (@MainActor @Sendable (Result<[Data], Error>) -> Void)?
    private var codeResult: (@MainActor @Sendable (String) -> Void)?
    private var operationEnded: (@MainActor @Sendable () async -> Void)?

    public init(presentationOwner: MiniAppPresentationOwner,
                present: @escaping Present, dismiss: @escaping Dismiss) {
        self.presentationOwner = presentationOwner
        self.present = present
        self.dismiss = dismiss
    }

    public func documentOperation(
        result: @escaping @MainActor @Sendable (Result<[Data], Error>) -> Void,
        ended: @escaping @MainActor @Sendable () async -> Void
    ) -> MiniAppCaptureOperation {
        MiniAppCaptureOperation(resources: [.camera]) { [weak self] in
            guard let self else { throw MiniAppCaptureFailure.stopped }
            guard VNDocumentCameraViewController.isSupported else { throw MiniAppCaptureFailure.unsupported }
            let controller = VNDocumentCameraViewController()
            controller.delegate = self
            self.documentResult = result
            self.operationEnded = ended
            try await self.begin(controller)
            return { [weak self] _ in await self?.end() }
        }
    }

    public func codeOperation(
        symbologies: [VNBarcodeSymbology] = [.qr],
        result: @escaping @MainActor @Sendable (String) -> Void,
        ended: @escaping @MainActor @Sendable () async -> Void
    ) -> MiniAppCaptureOperation {
        MiniAppCaptureOperation(resources: [.camera]) { [weak self] in
            guard let self else { throw MiniAppCaptureFailure.stopped }
            guard DataScannerViewController.isSupported else { throw MiniAppCaptureFailure.unsupported }
            guard DataScannerViewController.isAvailable else { throw MiniAppCaptureFailure.unavailable("data scanner") }
            let controller = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: symbologies)], qualityLevel: .balanced,
                recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true
            )
            controller.delegate = self
            self.codeResult = result
            self.operationEnded = ended
            try await self.begin(controller)
            try controller.startScanning()
            return { [weak self] _ in
                controller.stopScanning()
                await self?.end()
            }
        }
    }

    private func begin(_ controller: UIViewController) async throws {
        let handle = try presentationOwner.begin(.uiViewController) { [weak self] in await self?.dismiss() }
        self.handle = handle
        self.controller = controller
        do { try await present(controller) }
        catch {
            presentationOwner.didEnd(handle)
            self.handle = nil
            self.controller = nil
            throw error
        }
    }

    private func end() async {
        guard let handle else { return }
        await presentationOwner.end(handle)
        presentationOwner.didEnd(handle)
        self.handle = nil
        controller = nil
        documentResult = nil
        codeResult = nil
        operationEnded = nil
    }

    public func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                             didFinishWith scan: VNDocumentCameraScan) {
        let pages = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.9) }
        documentResult?(.success(pages))
        Task { @MainActor [weak self] in await self?.operationEnded?() }
    }

    public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        documentResult?(.failure(CancellationError()))
        Task { @MainActor [weak self] in await self?.operationEnded?() }
    }

    public func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                             didFailWithError error: Error) {
        documentResult?(.failure(error))
        Task { @MainActor [weak self] in await self?.operationEnded?() }
    }

    public func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue else { return }
        codeResult?(payload)
        Task { @MainActor [weak self] in await self?.operationEnded?() }
    }

    public func dataScanner(_ dataScanner: DataScannerViewController,
                            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
        Task { @MainActor [weak self] in await self?.operationEnded?() }
    }
}
#endif
