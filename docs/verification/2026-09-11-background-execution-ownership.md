# D17 UIKit background execution ownership verification

Updated: 2026-09-11

## Scope and primary contract

This unit covers `UIApplication.beginBackgroundTask(withName:expirationHandler:)`
and the matching `endBackgroundTask(_:)` call. Apple requires every successful
begin to be balanced by the exact returned identifier, permits multiple parallel
requests but requires each to end separately, calls expiration synchronously on
the main thread, and returns `.invalid` when background execution cannot be
granted.

Primary sources:

- [beginBackgroundTask(expirationHandler:)](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask%28expirationhandler%3A%29)
- [Extending your app's background execution time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)
- [backgroundTimeRemaining](https://developer.apple.com/documentation/uikit/uiapplication/backgroundtimeremaining)

The OS time window belongs to the host app, not to a Feature. This implementation
owns and balances tokens; it does not invent a generic scheduler or cover
`BGTaskScheduler` / `BGContinuedProcessingTask`.

## Deterministic tests

`MiniAppBackgroundExecutionTests` injects a native-shaped assertion provider and
checks:

- same operation names in two Features receive separate names/tokens;
- ending A leaves B active, and repeated `end()` does not call native end twice;
- expiration runs only A's cleanup, ends only A, and converges with explicit end;
- expiration delivered synchronously during acquisition still balances the token once;
- a denied begin returns nil and admits no operation;
- `MiniAppRuntime.shutdown()` ends all of its assertions exactly once while a
  second runtime stays active and later performs its own cleanup.
- manager deinitialization updates an externally retained lease, ends its native
  token once, and leaves another owner active.

The signed-host `BackgroundExecutionProbe` uses real `UIApplication` begin/end
calls for two Feature runtimes, proves A's explicit end and runtime shutdown do
not mark B ended, then waits for B runtime cleanup before reporting `passed`.

UIKit does not expose a supported API to force a real expiration callback, and
Simulator suspension timing is system-controlled. Therefore native acquisition
and end are covered in the signed host, while expiration ownership is covered by
the deterministic provider test. A Simulator run that never receives expiration
must not be reported as native expiration evidence.

The earlier Spotlight probe reports `passed` before its final B-domain cleanup;
its successful run proves the asserted A-delete/B-survival behavior, not that the
post-pass cleanup completed.

## CI evidence

Run 34512924037, source `67da73e5d6081abd109b90cf5f5a395a5c1ab7dd`,
passed shared feature logic, independent Feature packages, Xcode build, and IPA
packaging. Run 34513513425, source
`980a9126e20813dfc4a4feb894dd3c07dcd6d7e0`, then passed the signed isolated-host
selector in 18.128 seconds with `BACKGROUND_EXECUTION_UI result=passed`; the run
as a whole failed later in the unrelated existing Files backup UI check. An
identical rerun, 34517376263, completed successfully.

After review, manager deinitialization was changed to update externally retained
lease state while ending each native token once, and the public factory was
limited to UIKit platforms. Final run 34519837163, source
`5f4aa2e33ab4fdb994d649d0d48d76038a6c51f7`, completed all steps successfully:
150 shared tests had zero failures, build/IPA and simulator regressions passed,
and the signed `BackgroundExecutionUITests` selector passed in 18.539 seconds
with `BACKGROUND_EXECUTION_UI result=passed`.

No run above forces a system expiration callback. The deterministic expiration
tests are evidence for owner routing and double-end prevention; they are not
evidence that Simulator delivered a real UIKit expiration event.
