# iOS 26 continued processing

`MiniAppContinuedProcessingCenter` is the host-shared ownership boundary for work that a
person explicitly starts in the foreground and expects to continue after backgrounding the
app. It complements, rather than replaces, the existing APIs:

- use `MiniAppBackgroundTasks` for discretionary refresh and processing scheduled by the OS;
- use `MiniAppSharedRefreshCenter` when Features share the app-wide refresh opportunity;
- use background `URLSession` for OS-owned transfers and reconnect its delegate through
  `MiniAppBackgroundURLSessionReconnectRegistry`;
- use `MiniAppBackgroundExecution` only for short UIKit completion grace time.

Create one center for the host process, give each Feature an owner-limited handle, and register
the permitted identifier from `MiniAppDefinition.onHostLaunch` (or the Feature's equivalent
screen-independent integration hook):

```swift
let center = MiniAppContinuedProcessingCenter()
let tasks = center.tasks(for: MiniAppContext(id: featureID))

try tasks.register(identifier: "com.example.app.export") { execution in
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

Submit only as the immediate result of a foreground user action. `.queue` asks the system to
start as soon as capacity becomes available; `.fail` reports submission failure when it cannot
start immediately.

```swift
try tasks.submit(.init(
    identifier: "com.example.app.export",
    title: "Export video",
    subtitle: "Preparing",
    strategy: .queue
))
```

The Feature still owns the operation, results, checkpoints, and generation checks. An expiration
callback, including cancellation from the system Live Activity, is a cleanup request. Cancel the
work, await or otherwise finish cleanup, then call `complete(success: false)`. Completion is
idempotent, late expiration is not delivered to a completed execution, and the center retains an
execution until completion. `cancelPendingRequest` is owner checked and cancels only that exact
queued identifier; it is not process-wide cancellation and does not silently complete a running
operation.

Every registered identifier must be present in the composed host
`BGTaskSchedulerPermittedIdentifiers`. Static identifiers are simplest. iOS 26 also supports a
permitted wildcard suffix for dynamically composed continued-processing identifiers; if used,
the fully composed identifier still needs an explicit Feature ownership policy and registration.
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
- [Finish tasks in the background (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/227/)
