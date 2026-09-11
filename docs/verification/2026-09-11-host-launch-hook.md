# Feature host-launch hook guide (2026-09-11)

## Purpose

`MiniAppDefinition.onHostLaunch` is one synchronous, throwing hook for native registrations which must exist before any Feature screen is created. It is intentionally generic: BackgroundTasks launch handlers and notification/provider factories can use the same host boundary without a D15-specific switch or a second lifecycle model.

The hook is not an OS launch callback. It registers native providers during the host application's normal launch; provider acceptance does not imply that iOS will later grant a background execution opportunity.

## Host integration

The host calls every hook from its existing `application(_:didFinishLaunchingWithOptions:)` registration block:

```swift
for definition in MiniAppRegistry.all {
    try definition.onHostLaunch?()
}
```

Keep this in the same `do` / fail-fast error boundary as other native Feature registration. UIKit invokes `didFinishLaunchingWithOptions` once for a process launch. The host must not add silent deduplication: a repeated call should reach the provider, whose existing duplicate-registration error remains visible instead of being hidden.

## Fixture

`HostLaunchHookProbe` provides two Feature definitions. Each hook increments its own process-local registration count and traps on a second invocation. Their root views only read the resulting counts; they do not trigger registration. `HostLaunchHookUITests` launches the host, opens both screens afterward, and requires each count to be exactly one.

The generated-host integration needs these mechanical additions:

1. copy `HostLaunchHookProbe.swift` into `Sources/JibunKit`;
2. copy `HostLaunchHookUITests.swift` into `UITests`;
3. add both `HostLaunchHookProbe.definitions` entries to `MiniAppRegistry.all`;
4. invoke all `onHostLaunch` hooks inside the existing AppDelegate launch registration `do` block.

`NotificationAppDelegate.swift` is intentionally unchanged in this branch so the owner of the shared launch path can coordinate this call with concurrent D16 work.
