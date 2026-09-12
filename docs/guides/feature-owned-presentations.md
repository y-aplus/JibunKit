# Feature-owned presentations

Sheets, full-screen covers, and UIKit controllers belong to the Feature that
created them. A Feature can keep ordinary `@State` or an observable presentation
model in its root view; the host does not need one process-wide modal router.
The existing per-Feature `NavigationPath` remains the source of truth for pushed
destinations.

Use one `MiniAppPresentationOwner` per Feature and connect it while configuring
each new `MiniAppRuntime` generation:

```swift
@MainActor
final class ReminderPresentation {
    let owner = MiniAppPresentationOwner(id: MiniAppID("reminder"))

    func configure(runtime: MiniAppRuntime) throws {
        try owner.connect(to: runtime)
    }
}
```

When presenting a surface, register an async dismissal callback. That callback
must set the Feature's local binding to false and wait until SwiftUI's
`onDismiss` (or the equivalent UIKit completion) confirms that the surface has
actually ended. Call `didEnd` for user cancellation after the presentation has
already disappeared.

```swift
let handle = try presentations.begin(.sheet) {
    await sheetState.dismissAndWaitForOnDismiss()
}

// From the sheet modifier's onDismiss:
presentations.didEnd(handle)
sheetState.finishDismissal()
```

Runtime shutdown closes that owner's presentation admission, then awaits its
active surfaces in reverse presentation order. It never dismisses another
Feature's surfaces. A newly created runtime generation can reconnect the same
owner only after the previous shutdown has completed.

`MiniAppViewControllerAdapter` embeds a Feature-created `UIViewController` in a
SwiftUI presentation. Its factory receives a cancellation closure so UIKit UI
can update the Feature's own SwiftUI state. `didDismantle` is available for local
controller cleanup; lifecycle completion should still use the enclosing
presentation's actual dismissal acknowledgement.

External URLs and notifications continue to select a scene and Feature through
the existing routing contract. If that switch removes a presenting root view,
its normal dismissal callback must finish the old owner's handle. Returning to
the Feature uses its retained `NavigationPath`; an explicit path reset affects
only that Feature. Disabling or deleting a Feature must first close host entry,
then stop its runtime and await these dismissals before unregistering it. A
timeout is diagnostic information, not permission to continue deletion.
