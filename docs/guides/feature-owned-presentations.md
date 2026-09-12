# Feature-owned presentations

Sheets, full-screen covers, and UIKit controllers belong to the Feature that
created them. A Feature can keep ordinary `@State` or an observable presentation
model in its root view; the host does not need one process-wide modal router.
The existing per-Feature `NavigationPath` remains the source of truth for pushed
destinations.

The host retains each Feature's navigation path separately within a scene. An
ordinary switch resumes that path; an explicit root URL or the host's reset
command clears only the addressed path. Switching can recreate the root View,
so a View-local `@State` is not a promise that an unsaved draft survives. Keep
drafts, selection, and other state that must survive in a Feature-owned model
retained outside that View, then bind it from the recreated root. The presentation
fixture demonstrates this with independent A/B drafts. Runtime stop does not
automatically erase such models; the Feature decides which state to reset on
shutdown/reconfiguration, and its removal provider deletes owned saved data.

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
owner only after the previous shutdown has completed. Once the connected
runtime has closed admission, new presentations are rejected even while its
tasks are still ending. Concurrent stop and explicit dismissal requests join
the same per-surface dismissal instead of invoking its callback twice.

`MiniAppViewControllerAdapter` embeds a Feature-created `UIViewController` in a
SwiftUI presentation. Its factory receives a cancellation closure so UIKit UI
can update the Feature's own SwiftUI state. `didDismantle` is available for local
controller cleanup; lifecycle completion should still use the enclosing
presentation's actual dismissal acknowledgement. SwiftUI updates refresh the
adapter coordinator's callbacks, so a retained controller never calls a stale
Feature closure after its representable value changes.

Connect the same owner through `MiniAppDefinition(presentations: owner, ...)`.
External URLs, notifications, and menu selection then ask that owner to dismiss
its active surfaces **before** removing the old root. Navigation waits for the
native acknowledgement; repeated selection requests keep the latest target.
This preserves the runtime connection, so returning to the Feature can present
again. Features without owned presentations keep the synchronous routing path.

The lifetime destination also keeps its running content mounted during stopping,
with interaction disabled, until runtime cleanup has finished. Removing that
content when stopping begins would lose SwiftUI onDismiss and could stall
shutdown forever. Disabling the owner closes new entry first but keeps the old
presenter/path alive until departure acknowledgement. Saved path removal occurs
afterwards. These are host responsibilities, not a requirement for the Feature
to fake dismissal from onDisappear or dismantle.

An explicit path reset still affects only that Feature. Runtime shutdown and
navigation dismissal share the in-flight callback; shutdown closes the generation
while navigation alone leaves it connected. A timeout diagnoses an unfinished
operation and never authorizes deleting data or dropping the acknowledgement.
