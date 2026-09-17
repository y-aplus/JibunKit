#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
import Foundation

@available(iOS 26.0, *)
@MainActor
private final class SystemContinuedProcessingTask: MiniAppContinuedProcessingNative {
    private let task: BGContinuedProcessingTask
    private var bridgedExpirationHandler: (@MainActor @Sendable () -> Void)?

    init(_ task: BGContinuedProcessingTask) { self.task = task }

    var expirationHandler: (@MainActor @Sendable () -> Void)? {
        get { bridgedExpirationHandler }
        set {
            bridgedExpirationHandler = newValue
            task.expirationHandler = newValue.map { handler in
                { MiniAppBackgroundTaskActorBridge.deliverExpiration(handler) }
            }
        }
    }

    func updateProgress(completed: Int64, total: Int64) {
        task.progress.totalUnitCount = total
        task.progress.completedUnitCount = completed
    }

    func updateTitle(_ title: String, subtitle: String) {
        task.updateTitle(title, subtitle: subtitle)
    }

    func setTaskCompleted(success: Bool) { task.setTaskCompleted(success: success) }
}

@available(iOS 26.0, *)
@MainActor
private final class SystemContinuedProcessingScheduler: MiniAppContinuedProcessingScheduling {
    private let scheduler: BGTaskScheduler

    init(_ scheduler: BGTaskScheduler) { self.scheduler = scheduler }

    func register(
        identifier: String,
        launch: @escaping @MainActor (any MiniAppContinuedProcessingNative) -> Void
    ) -> Bool {
        scheduler.register(forTaskWithIdentifier: MiniAppBackgroundTaskIdentifier.resolve(identifier), using: .main) { task in
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in launch(SystemContinuedProcessingTask(continued)) }
        }
    }

    func submit(_ request: MiniAppContinuedProcessingRequest) throws {
        let native = BGContinuedProcessingTaskRequest(
            identifier: MiniAppBackgroundTaskIdentifier.resolve(request.identifier),
            title: request.title,
            subtitle: request.subtitle
        )
        native.strategy = request.strategy == .queue ? .queue : .fail
        try scheduler.submit(native)
    }

    func cancel(identifier: String) {
        scheduler.cancel(taskRequestWithIdentifier: MiniAppBackgroundTaskIdentifier.resolve(identifier))
    }
}

@available(iOS 26.0, *)
public extension MiniAppContinuedProcessingCenter {
    convenience init(scheduler: BGTaskScheduler = .shared) {
        self.init(scheduler: SystemContinuedProcessingScheduler(scheduler))
    }
}
#endif
