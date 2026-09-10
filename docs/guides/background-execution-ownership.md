# UIKit background execution ownership

`MiniAppBackgroundExecution` keeps each `beginBackgroundTask` token under the
Feature runtime that requested it. Create it from `MiniAppRuntime`, request a
lease before starting critical work, and end that lease immediately when the
work finishes.

```swift
let execution = try runtime.makeBackgroundExecution(context: context)
guard let lease = try execution.begin(operation: "save", onExpiration: {
    cancelOrCheckpointSave()
}) else {
    // UIKit returned .invalid. Do not start work that requires extra time.
    return
}

defer { lease.end() }
await save()
```

The operation name is namespaced for debugger visibility. A lease balances the
exact native token once: explicit completion, expiration, deinitialization, and
runtime shutdown converge on the same idempotent end path. Expiration invokes
only that operation's cleanup before ending its token. Shutting down one runtime
does not end another Feature's leases.

The UIKit factory is available only on platforms that provide `UIApplication`;
unsupported platforms do not expose a public factory that traps at runtime.

This is ownership bookkeeping, not a private time allocation. UIKit grants a
finite execution window to the host app, and `backgroundTimeRemaining` describes
that shared app window. A Feature cannot reserve or extend its own independent
quota. A nil lease means UIKit returned `.invalid`; treat this as failure to
obtain grace time rather than silently continuing protected work.

Use the original UIKit mechanism for short, critical completion work. This API
does not schedule future work and does not wrap `BGTaskScheduler` or
`BGContinuedProcessingTask`.
