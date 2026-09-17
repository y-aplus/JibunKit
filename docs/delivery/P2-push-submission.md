# P2-I Push submission

## Contract delivered

- App-level APNs token is held once by `MiniAppRemotePushCoordinator`; Feature/server identity remains owner-scoped.
- Token replacement fans out only to connected owner generations. Registration failure is distinct from provider/server failure.
- `MiniAppRemotePushService` binds registration and delivery to `MiniAppRuntime`; stop removes that generation, stale cleanup cannot remove its replacement, and management unregister affects one owner.
- Existing `MiniAppNotificationRoute` keys select exactly one owner for foreground/background payload work. Missing, invalid, stopped, or unregistered owners return `noData` rather than broadcasting.
- `MiniAppRemotePushCompletionAggregator` performs one-shot completion fan-in with `failed > newData > noData` precedence.
- `Tests/P2Push/P2PushProbe.swift` exposes two ordinary `MiniAppDefinition`s using the same local account identifier but separate server identities, lifetimes and unregister hooks.

## UIApplicationDelegate integration

The exact three callbacks and result mapping are documented in `docs/guides/remote-push.md`: forward `didRegisterForRemoteNotificationsWithDeviceToken`, `didFailToRegisterForRemoteNotificationsWithError`, and `didReceiveRemoteNotification:fetchCompletionHandler:` to `MiniAppRemotePushCoordinator.shared` on `MainActor`. Call `UIApplication.registerForRemoteNotifications()` once at host policy level. The parent owns the host wiring, so `Sources/JibunKit/NotificationAppDelegate.swift`, `Project.swift`, workflow and shared ledgers were not edited.

## Native/extension boundary

Coordinator callback tests are fakes and are not described as APNs success. Actual success requires a signed physical-device build, Push Notifications capability/profile, correct `aps-environment`, an APNs provider credential and environment-matched token. Background delivery also needs the Remote notifications background mode and remains OS-scheduled.

No notification service/content extension is required for ordinary owner routing, actions, presentation or background delivery. The guide gives the concrete opt-in connection for mutable-content transformation (owner-namespaced app-group handoff, no Feature runtime in the extension) and reserves a content extension for custom notification UI. Their separate signing targets are deliberately outside the normal core scope.

## Verification

Source tests cover token change/idempotence, separate server identity, registration failure, owner-only delivery, malformed/unowned rejection, stop and generation replacement, owner unregister preserving the other Feature, and exact-once completion aggregation. Native fixture tests cover two real definitions, same local account/separate servers, correct-owner delivery, independent lifetime stop, and unregister isolation.

- `swift test --filter MiniAppRemotePushTests`: not run on this Windows worker because no Swift executable/toolchain is installed.
- P2 native fixture tests: not run here; the parent task owns generated iOS host integration and CI.
- Static inspection: completed for owned paths and existing route/lifetime/runtime reuse.

## Commit

Commit SHA: `TO_BE_FILLED_AFTER_COMMIT`
