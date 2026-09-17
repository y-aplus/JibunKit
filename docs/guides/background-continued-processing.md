# iOS 26 continued processing

`MiniAppContinuedProcessingCenter` is the host-shared ownership boundary for work that a
person explicitly starts in the foreground and expects to continue after backgrounding the
app. It complements, rather than replaces, the existing APIs:

- use `MiniAppBackgroundTasks` for discretionary refresh and processing scheduled by the OS;
- use `MiniAppSharedRefreshCenter` when Features share the app-wide refresh opportunity;
- use background `URLSession` for OS-owned transfers and reconnect its delegate through
  `MiniAppBackgroundURLSessionReconnectRegistry`;
- use `MiniAppBackgroundExecution` only for short UIKit completion grace time.

Create one center for the host process and give each Feature an owner-limited handle. Put a
wildcard base in `BGTaskSchedulerPermittedIdentifiers`, for example
`com.example.app.export.*`. A foreground user action constructs one request with a unique UUID
suffix; JibunKit registers that fully composed identifier and submits it as one operation:

```swift
let center = MiniAppContinuedProcessingCenter()
let tasks = center.tasks(for: MiniAppContext(id: featureID))
let request = MiniAppContinuedProcessingRequest(
    baseIdentifier: "com.example.app.export",
    title: "Export video",
    subtitle: "Preparing",
    strategy: .queue
)
let receipt = try tasks.submit(request) { execution in
    execution.onExpiration = { cancelAndCheckpointExport() }
    startExport(
        progress: { completed, total in
            execution.reportProgress(completed: completed, total: total)
            execution.updateTitle("Export", subtitle: "\(completed) / \(total)")
        },
        completion: { success in execution.complete(success: success) }
    )
}
```

Submit only as the immediate result of a foreground user action. The request exposes the exact
`identifier` (`baseIdentifier.UUID`) and its matching `permittedIdentifier`
(`baseIdentifier.*`). Never reuse a job UUID in one process. `.queue` asks the system to start as
soon as capacity becomes available; `.fail` reports submission failure when it cannot start
immediately. Continued-processing launch handlers are intentionally registered at this user
intent point; unlike refresh and processing handlers, Apple does not require these handlers to be
registered during app launch.

The Feature still owns the operation, results, checkpoints, and generation checks. An expiration
callback, including cancellation from the system Live Activity, is a cleanup request. Cancel the
work, await or otherwise finish cleanup, then call `complete(success: false)`. Completion is
idempotent, late expiration is not delivered to a completed execution, and the center retains an
execution until completion. `cancelPendingRequest` is owner checked and cancels only that exact
queued identifier; it is not process-wide cancellation and does not silently complete a running
operation.

The wildcard base, including its literal trailing `.*`, must be present in the composed host
`BGTaskSchedulerPermittedIdentifiers`. The fully composed identifier passed to registration and
submission contains a nonempty unique suffix matching that wildcard. JibunKit records its owner,
rejects duplicate UUIDs, and fails a late native launch if the center has already been released.
Do not request background GPU resources through this wrapper: GPU capability and entitlement are
an optional, separate integration and are outside this boundary.

The system owns admission and runtime. A successful `submit` does not prove launch, and invoking a
stored launch closure in a test is not OS-launch evidence. The system may terminate work under
resource pressure, cancels queued work when a person closes the app from the app switcher, and may
terminate running work there without delivering an expiration callback. Persist recoverable
Feature state independently of the execution object.

Apple references:

- [Performing long-running tasks on iOS and iPadOS](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)
- [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)
- [BGContinuedProcessingTaskRequest](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest)
- [`BGContinuedProcessingTaskRequest.init(identifier:title:subtitle:)`](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest/init(identifier:title:subtitle:))
- [Finish tasks in the background (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/227/)
