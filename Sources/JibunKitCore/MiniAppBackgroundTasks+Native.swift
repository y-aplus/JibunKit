#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
import Foundation

@MainActor
private final class SystemBackgroundTask: MiniAppBackgroundTaskNative {
    private let task: BGTask

    init(_ task: BGTask) { self.task = task }

    var expirationHandler: (() -> Void)? {
        get { task.expirationHandler }
        set { task.expirationHandler = newValue }
    }

    func setTaskCompleted(success: Bool) { task.setTaskCompleted(success: success) }
}

@MainActor
private final class SystemBackgroundTaskScheduler: MiniAppBackgroundTaskScheduling {
    private let scheduler: BGTaskScheduler

    init(_ scheduler: BGTaskScheduler) { self.scheduler = scheduler }

    func register(
        identifier: String,
        kind: MiniAppBackgroundTaskKind,
        launch: @escaping @MainActor (any MiniAppBackgroundTaskNative) -> Void
    ) -> Bool {
        scheduler.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { launch(SystemBackgroundTask(task)) }
        }
    }

    func submit(_ request: MiniAppBackgroundTaskRequest, kind: MiniAppBackgroundTaskKind) throws {
        let native: BGTaskRequest
        switch kind {
        case .appRefresh:
            native = BGAppRefreshTaskRequest(identifier: request.identifier)
        case let .processing(network, power):
            let processing = BGProcessingTaskRequest(identifier: request.identifier)
            processing.requiresNetworkConnectivity = network
            processing.requiresExternalPower = power
            native = processing
        }
        native.earliestBeginDate = request.earliestBeginDate
        try scheduler.submit(native)
    }

    func cancel(identifier: String) {
        scheduler.cancel(taskRequestWithIdentifier: identifier)
    }
}

public extension MiniAppBackgroundTaskCenter {
    convenience init(scheduler: BGTaskScheduler = .shared) {
        self.init(scheduler: SystemBackgroundTaskScheduler(scheduler))
    }
}
#endif

