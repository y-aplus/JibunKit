# Runtime shutdown progress

`MiniAppRuntime.shutdownProgress` is a snapshot for diagnostics and host UI. It
reports the current phase, tasks that have not actually returned, cleanups that
have not actually finished, and the time at which shutdown first started.

```swift
let progress = runtime.shutdownProgress

switch progress.phase {
case .active:
    break
case .waitingForTasks, .runningCleanups:
    logger.info("Shutdown still in progress: \(progress)")
case .completed:
    break
}
```

Calling `cancelTasks()` only requests cooperative cancellation. It does not
start shutdown and does not make a pending task disappear from the snapshot.
Likewise, `shutdown()` does not report completion until every owned task has
returned and every registered cleanup has completed in reverse registration
order. A concurrent caller joins that same shutdown.

## Keep the main actor responsive

Runtime coordination and cleanup run on the main actor. Never wait there with a
semaphore, a sleep, a spin loop, synchronous network or file I/O, or a blocking
database call. Start cancellable asynchronous work with `runtime.start`, use APIs
that suspend while waiting, and make resource release asynchronous with
`onShutdownAsync` when it cannot finish immediately.

Not every small operation needs lifecycle compensation. Bounded local work that
finishes in the same turn and owns no resource can stay inline, for example:

- validating a value already in memory;
- formatting a short label;
- deriving a small value-type view model;
- copying or sorting a small, fixed-size local collection.

Once work can outlive the call, mutate persistent or remote state, or acquire a
resource, give it explicit runtime ownership and register the corresponding
cleanup or recovery behavior.
