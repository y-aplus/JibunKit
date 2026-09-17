# P2-4 background delivery proposal

Date: 2026-09-17
Baseline: `57542e66981373d2de3d112aca91ea1aa56c07cf`

## Decision and implementation

The existing background components remain the normal implementation:

- `MiniAppBackgroundTaskCenter` already preserves `BGAppRefreshTaskRequest` and
  `BGProcessingTaskRequest`, launch/expiration/completion, exact owner cancellation, and native
  registration rejection.
- `MiniAppSharedRefreshCenter` plus `FileSharedRefreshJournal` already persists pending/running/
  recovery generations, reconnects registered Feature handlers after cold process launch, and
  completes the native batch only after every logical job finishes.
- `MiniAppBackgroundURLSessionReconnectRegistry` already derives stable owner/profile identifiers,
  joins duplicate host callbacks, retains every completion until the Feature delegate reports
  `urlSessionDidFinishEvents`, and protects replacements from stale registration/event tokens.
- `MiniAppBackgroundExecution` remains the short UIKit grace-time API and is not presented as a
  scheduler.

The missing iOS 26 path is implemented as `MiniAppContinuedProcessingCenter`. It keeps exact
identifier ownership, forwards `.queue`/`.fail`, title and subtitle, exposes native progress and
title updates, hops expiration to `MainActor`, retains each launched execution through asynchronous
cleanup, and completes the native task exactly once. Pending cancellation is exact and owner
checked. The wrapper intentionally excludes optional GPU resources and does not turn user-initiated
work into automatic maintenance.

`P2BackgroundProbe.definitions` supplies two real Feature definitions. Each launch hook registers
an ordinary refresh/processing identifier, one owner in the durable shared-refresh journal, a
background URLSession reconnect factory, and a continued-processing identifier. Its UI submits
continued work from a button, reports measurable progress, handles expiration/cancellation, and
uses a generation check so a stale job cannot finish a replacement. This is a diagnostic Feature,
not product data storage.

## Acceptance coverage

| Requirement | Automated/native coverage | Evidence meaning |
| --- | --- | --- |
| Two owners, registration and launch routing | Existing `MiniAppBackgroundTasksTests`; new `MiniAppContinuedProcessingTests.testTwoOwnersReceiveOnlyTheirLaunchAndProgress` | Deterministic provider routing, not OS launch |
| Refresh/processing request options and scoped cancellation | Existing `MiniAppBackgroundTasksTests` and `BackgroundTasksNative` fixture | Core regression; signed device still required for accepted native pending requests |
| Shared refresh cold recovery, batch expiration, acknowledgement failure, other-owner retention | Existing `MiniAppSharedRefreshTests` and journal tests | Durable model/provider coverage |
| Background transfer owner/profile, duplicate callback join, delegate-finish completion | Existing `MiniAppBackgroundURLSessionReconnectTests` and signed Simulator HTTP comparison | Warm host and real HTTP are proven; cold OS callback is not |
| Continued request presentation and queue/fail strategy | New Core test and `P2BackgroundNativeTests.testCurrentSDKConstructsContinuedRequestsWithPresentationAndStrategies` | Core forwarding plus current iOS SDK construction |
| Continued progress, displayed title, expiration cleanup, completion once | New `MiniAppContinuedProcessingTests` and real Feature probe | Provider behavior and Feature integration; system Live Activity/expiration remains device evidence |
| Rejected registration and cross-owner submit/cancel | New Core failure tests | No ownership claim or foreign cancellation on failure |
| Real Feature launch hooks | `P2BackgroundNativeTests.testDefinitionsExposeTwoIndependentHostLaunchRegistrations` | Definition wiring; host must invoke hooks at launch |

## Shared integration changes requested from the parent

No shared file was edited in this lane. Integration needs these concrete changes in the parent's
owned files:

1. Add `Tests/P2Background/P2BackgroundProbe.swift` to the diagnostic app source list and
   `Tests/P2Background/P2BackgroundNativeTests.swift` to its native test target. Append
   `P2BackgroundProbe.definitions` at the diagnostic composition point; do not add the fixtures to
   the production Feature registry.
2. During `application(_:didFinishLaunchingWithOptions:)`, enumerate the composed definitions and
   call every `definition.onHostLaunch` before returning. The existing host launch hook is the
   intended call site; do not register these from a screen.
3. Add these exact values to the diagnostic host's composed
   `BGTaskSchedulerPermittedIdentifiers`:
   `com.jibunkit.app.p2-background-a.ordinary`,
   `com.jibunkit.app.p2-background-b.ordinary`,
   `com.jibunkit.app.p2-background.shared-refresh`,
   `com.jibunkit.app.p2-background-a.export`, and
   `com.jibunkit.app.p2-background-b.export`. Keep `processing` in `UIBackgroundModes` for the
   processing/shared-refresh paths. No continued-processing GPU entitlement is requested.
4. In the existing `UIApplicationDelegate.application(_:handleEventsForBackgroundURLSession:
   completionHandler:)`, forward the identifier and completion to
   `MiniAppBackgroundURLSessionReconnectRegistry.shared.handleEvents(...)`. This must run after
   launch hooks have registered factories and must not call the completion separately.

## Verification performed in this lane

- `git diff --check`: passed with no whitespace errors. Source/reference inspection also passed.
- Swift/Core tests: not executable on this Windows worker because no Swift toolchain is installed.
- iOS SDK build and native XCTest: not executable on Windows. The native test is supplied for the
  parent's macOS/Xcode 26 integration run.
- No Simulator scheduler submission was retried. The known Xcode 26.6 / iOS 26.5 Simulator result
  in `docs/verification/2026-09-11-backgroundtasks-native-pending.md` is
  `BGTaskScheduler.Error.Code.unavailable` for both direct and wrapped requests; repeating it would
  not add evidence.
- The existing signed Simulator real-HTTP comparison in
  `docs/verification/2026-09-11-background-urlsession-native-http.md` remains valid for warm-host
  native download/cancel isolation. This change does not replace its URLSession code.

## Device acceptance and unresolved conditions

On a signed physical iOS 26 device, the parent should run the diagnostic host and distinguish the
following observations:

1. A foreground tap submits each continued task; an actual system launch displays its Live
   Activity and advances 1 through 10. This is OS launch evidence. Directly invoking a handler is
   not.
2. Cancel owner A from the system interface while B runs. A must finish cleanup as unsuccessful;
   B must continue and complete. Repeat Feature-side cancellation for exact pending ownership.
3. For ordinary refresh/processing and shared refresh, accepted submission/pending request is one
   boundary; a later OS-chosen launch is separate. Capture both without treating delayed scheduling
   as a JibunKit failure.
4. Start real background downloads for A/B, background or terminate normally, and confirm the OS
   calls the app delegate, both factories reconnect without screens, and every host completion is
   released only after the corresponding delegate finish. Force-quit behavior and SideStore
   re-signing remain OS/deployment conditions, not guaranteed recovery.

Unresolved until that run: physical-device continued-processing admission/Live Activity/system
cancellation, real BGTask OS launch/expiration, background URLSession cold-launch delivery, and
SideStore re-sign identifier continuity. No iOS execution is claimed by this Windows submission.
