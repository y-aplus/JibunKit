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
