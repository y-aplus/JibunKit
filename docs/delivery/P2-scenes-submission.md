# P2 scene submission

## Delivered

- A process registry separating stable OS session identity from ephemeral connection generation.
- Exact-session route delivery with stale-generation rejection.
- Scene-scoped, owner-grouped cleanup; closing/replacing one connection preserves other windows and does not stop Feature-global runtime.
- UIKit request adapter for OS window creation/destruction without treating request acceptance as successful window creation.
- Core tests for two-window isolation, close/other-window retention, cleanup order, restoration, late delivery, and stale disconnect.
- An iOS probe with two normal `MiniAppDefinition` values, per-window `@SceneStorage`, and a native diagnostic that requires two real `UIWindowScene` sessions.

## Parent-owned integration diff

No parent-owned file was edited. The required host/manifest/test-target changes are listed step by step in [window-scene-ownership.md](../guides/window-scene-ownership.md#host-connection). In summary: enable multiple scenes, connect the real `UISceneSession.persistentIdentifier` at the existing `WindowGroup` root, keep the returned generation, disconnect only on genuine UIScene disconnection, use explicit session delivery when known, add the two probe definitions to the normal registry, and compile the P2Scenes files in the diagnostic target.

The existing `MiniAppSceneRouter` needs no change: it remains the fallback for process events with no OS session target. The new registry handles the distinct explicit-session contract.

## Validation boundary

The core tests are meaningful model/ownership checks but are not proof that iPadOS created two windows. `P2ScenesNativeTests.testIPadHostHasTwoDistinctOSWindowSessionsForManualScenario` skips unless it observes two distinct live OS sessions. A parent CI or manual run must separately report iPad Simulator and device evidence.

This worker ran on Windows where `swift` is unavailable, so no Swift build or test is recorded as executed. `git diff --check` and path-boundary inspection were run. The UIKit signatures were checked against Apple documentation for `UISceneSessionActivationRequest`, `activateSceneSession(for:errorHandler:)`, `requestSceneSessionDestruction(_:options:errorHandler:)`, `openSessions`, and `UISceneSession.persistentIdentifier`; compilation remains for the parent Xcode boundary.

Swift 6 review points: public mutable coordinators and callbacks are `@MainActor`; escaping callbacks retain no host navigation in the core; callers are instructed to capture the window root weakly; async cleanup closures execute on `MainActor`; XCTest classes containing async actor-isolated tests opt out of implicit Sendable checking. The UIKit requester and its sendable failure callback are both `MainActor` isolated.

## Not claimed

- No actual iPad Simulator/device two-window operation has been run by this Windows worker.
- OS state restoration beyond values the host explicitly places in `SceneStorage` is not promised.
- Window request acceptance is not counted as creation or destruction.
- Feature disable/removal/restore orchestration remains in the existing global management lifecycle; this registry does not replace it.
