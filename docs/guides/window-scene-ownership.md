# Window scene ownership

## Ownership model

The host creates one `MiniAppWindowSceneRegistry` for the process and one connection for each actual `WindowGroup` scene. `MiniAppWindowSessionID` is the stable `UISceneSession.persistentIdentifier`; `MiniAppWindowConnection.generation` identifies only the current connection. Reconnecting a restored session retains the former session ID but invalidates its old generation, route callbacks, and scene-scoped resources.

Each window root continues to own its `AppNavigation`, `@SceneStorage`, search state, and presentation state. The registry stores none of those values and does not require Feature navigation values or arbitrary views to conform to `Codable`. A Feature-global `MiniAppRuntime` is also not owned by the scene registry: closing one window must not stop the same Feature in another window.

Use `onDisconnect(owner:connection:_:)` only for resources tied to that window (for example a scene observer or presenter). Explicit disconnect and replacement release those resources. They do not call `MiniAppRuntime.shutdown()`. Feature disable/removal/restore must first stop and join the global Feature lifetime through the existing management path; only then should owned persistent state be deleted or replaced.

## Host connection

The host-owned `Sources/JibunKit`, `Project.swift`, manifest, and workflow are intentionally not changed by this submission. The host must make these concrete changes:

1. Enable multiple scenes with `UIApplicationSupportsMultipleScenes = true` in the application scene manifest. Keep the normal `WindowGroup`; do not add a second navigation singleton.
2. At scene connection, obtain the real session ID from the corresponding `UIWindowScene.session.persistentIdentifier`, then `await registry.connect(sessionID:phase:selectedID:route:)`. The route closure must target that root's existing `AppNavigation` weakly or through the root's owned binding.
3. Store the returned `MiniAppWindowConnection` in the root/scene bridge. Forward root `scenePhase` and selected Feature changes with `update`. On genuine `sceneDidDisconnect` (not SwiftUI `onDisappear` during full-screen presentation), await `disconnect`.
4. For an event already associated with a scene, call `open(_:in:expected:)` with both its stable session ID and captured connection. Treat `staleConnection` as a dropped late callback. Keep `MiniAppSceneRouter` for process-level notifications that have no target session.
5. Use `MiniAppUIKitWindowSceneRequester.requestWindow` for “New Window” and `destroyWindow` for an explicit close command. A successful request call is only acceptance by UIKit; count actual connected `UIWindowScene` sessions before claiming success.
6. Include `Tests/P2Scenes/P2ScenesProbe.swift` and `P2ScenesNativeTests.swift` in the parent-owned diagnostic target. Add both probe definitions to the normal registry so they traverse normal selection, lifetime, and navigation code.

## iPad verification

On an iPad Simulator and separately on an iPad device when available:

- Open a second window through the app's New Window action or iPad multitasking UI. Verify two distinct `UISceneSession.persistentIdentifier` values; two Swift objects alone do not satisfy this check.
- Select A in window 1 and B in window 2, increment each counter to different values, navigate each to a different destination, then target each session explicitly. Verify neither window changes the other's selection, route, or counter.
- Close window 1. Verify its scene resources release while window 2 retains its counter, route, selected Feature, and global Feature work.
- Reopen/restore window 1. Verify its stable session identity where iPadOS restores the same session, a new connection generation, `@SceneStorage` recovery as supplied by the OS, and rejection of a callback carrying the old generation.
- Record request errors, actual session connect/disconnect callbacks, and session IDs. Do not describe adapter compilation, fake callbacks, or a skipped one-window run as an OS multiwindow pass.

Simulator and device results must be reported separately. OS termination may discard in-memory navigation; only explicitly `@SceneStorage`-backed values are expected to restore, and arbitrary Feature view serialization is outside this contract.
