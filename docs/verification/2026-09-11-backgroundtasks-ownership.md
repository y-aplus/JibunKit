# BackgroundTasks ownership verification (2026-09-11)

## Scope

This D15 unit covers standard `BGAppRefreshTask` and `BGProcessingTask` registration and launch delivery, owner-limited pending request cancellation, expiration delivery, and completion exactly once. It is separate from D17's UIKit background-time assertions in `MiniAppBackgroundExecution`.

## Apple boundary

`BGTaskScheduler` is process-wide. Every permitted identifier must be registered before application launch finishes, and Apple requires each identifier to be registered only once. Submission asks the system to schedule work; it does not guarantee a launch time or that a submitted request will run. When the system launches a task it supplies `BGTask`, whose expiration handler is the warning boundary and whose `setTaskCompleted(success:)` reports the final result.

The host therefore owns one `MiniAppBackgroundTaskCenter`. It creates an owner-limited `MiniAppBackgroundTasks` handle for each `MiniAppContext`. Registration records one owner and request kind for each native identifier before forwarding the registration to the provider. A second owner cannot claim the same identifier.

## Native/provider boundary

The iOS provider preserves the standard request types:

- `.appRefresh` creates `BGAppRefreshTaskRequest`;
- `.processing` creates `BGProcessingTaskRequest`; each submitted request independently forwards its network and external-power requirements;
- both forward `earliestBeginDate`;
- cancellation calls `cancel(taskRequestWithIdentifier:)`, never process-wide `cancelAllTaskRequests()`.

The core center does not simulate or promise OS launch opportunity. Tests replace only the provider boundary so launch, expiration, completion, submission options, and cancellation can be deterministic.

Apple does not document an actor or queue guarantee for `BGTask.expirationHandler`, and documents that the manager clears it after invocation. The native adapter therefore hops every expiration signal explicitly to `MainActor`. The host center, rather than the native closure, retains each in-flight execution until `complete(success:)`; this also supports asynchronous expiration cleanup after the OS has cleared its handler.

## Build requirements

Every registered identifier must also appear in the composed host Info.plist under `BGTaskSchedulerPermittedIdentifiers`. Processing tasks additionally require the applicable `UIBackgroundModes` entry. The existing `FeatureBuildConfiguration` string-set composition and its build-requirement probe already merge and verify these keys; runtime registration does not mutate Info.plist.

## Verification

The bounded core tests compare two Feature owners and verify:

1. each native launch reaches only the handler registered for that identifier;
2. refresh and processing request types and options survive submission, including changing processing conditions between submissions of one identifier;
3. processing-only network or power requirements on an app-refresh request fail explicitly rather than being discarded;
4. one owner's bulk cancellation touches only its registered identifiers;
5. duplicate cross-owner registration is rejected before a second native registration attempt;
6. expiration and native completion are each delivered at most once;
7. the center retains an execution after the OS-equivalent expiration handler is cleared, then releases it on completion;
8. an expiration signal originating off the main thread reaches its handler on `MainActor`;
9. a provider-rejected registration does not retain an ownership claim.

CI run [34550935682](https://github.com/y-aplus/JibunKit/actions/runs/34550935682), source `5c3d3a094ca8a5257ac98923b306f4d0ffb1db5a`, passed. All six focused ownership/lifecycle tests passed as part of 173 shared tests. FeatureBuildRequirements verification, native Feature template verification, generated workspace build, Xcode build, signing, and packaging also passed. This validates compilation of the iOS `BackgroundTasks` provider without claiming that the OS will choose to launch a submitted request.

Follow-up CI run [34551664876](https://github.com/y-aplus/JibunKit/actions/runs/34551664876), source `d14a7afa5f56736dedafdc4326904ca934f8e3be`, passed after moving processing conditions onto each submitted request and adding the execution-retention test. All seven BackgroundTasks tests passed as part of 174 shared tests; the same build-requirement, native-template, generated-workspace, Xcode build, signing, and packaging stages passed. The iOS adapter explicitly hops from the scheduler's launch queue into `MainActor` before creating and delivering the execution.

Apple references:

- [`BGTaskScheduler.register(forTaskWithIdentifier:using:launchHandler:)`](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register%28fortaskwithidentifier%3Ausing%3Alaunchhandler%3A%29)
- [`BGTaskScheduler`](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler)
- [`BGTask.expirationHandler`](https://developer.apple.com/documentation/backgroundtasks/bgtask/expirationhandler)
- [`BGProcessingTaskRequest`](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtaskrequest)
