# BackgroundTasks native pending request comparison

This bounded fixture compares JibunKit's owner-scoped BackgroundTasks API with direct
`BGTaskScheduler` requests on iOS Simulator. Two Feature definitions register their
refresh and processing identifiers through `onHostLaunch`; two additional identifiers
provide the direct native baseline.

The app submits all four requests and reads the OS-owned state with
`getPendingTaskRequests`. It checks concrete request subclasses, earliest begin dates,
and processing network/power conditions. It then cancels owner A's wrapper request and
the matching native baseline request and requires both B requests to remain pending.

The fixture declares every identifier in `BGTaskSchedulerPermittedIdentifiers` and
declares `fetch` and `processing` in `UIBackgroundModes`. A rejected registration or
submission fails the focused test; it is not converted into a skip or pass.

This does not claim an OS-scheduled task launch or expiration callback. Those require an
OS execution opportunity and remain a separate device boundary. CI evidence is added
after the focused run completes.

## Simulator result

Focused run [34559611951](https://github.com/y-aplus/JibunKit/actions/runs/34559611951),
source `f2f15cbbae36357f0f6c2b71b2378959312e4435`, compiled and launched the fixture on
Xcode 26.6 / iPhone 17 Simulator (iOS 26.5). Both independently attempted submissions
were rejected at the native scheduler boundary:

`failed: submissionRejected(wrapperCode: Optional(1), nativeCode: Optional(1))`

The focused XCTest failed, as intended for an unfulfilled native evidence requirement;
the rejection was not changed into a skip or pass. Code 1 is
[`BGTaskScheduler.Error.Code.unavailable`](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/error/code/unavailable).
Apple documents Simulator lack of background processing as one reason for this result.
Because the direct `BGAppRefreshTaskRequest` and the request submitted through
`MiniAppBackgroundTasks` fail identically, this run finds no adapter-specific mismatch.

Consequently, this Simulator cannot supply pending requests to compare. Request kind,
earliest begin date, processing network/power conditions, owner-A cancellation, and
owner-B pending survival remain implemented assertions but are not execution evidence.
They require a signed physical-device run where the OS accepts submission. Task launch
and expiration remain later OS-opportunity boundaries even on that device.

The failed run still uploaded `BackgroundTasks-diagnostics` (artifact ID `10184054885`,
SHA-256 `63149b34be5e506690a519bf9e8aba2754d7f9cd7fc3dd50d1ab752dd12849ec`).

Separate same-source run
[34560343510](https://github.com/y-aplus/JibunKit/actions/runs/34560343510) passed the
normal focused regression
`MigrationUITests/testMiniAppSearchFiltersAndOpensResults` in 41.676 seconds, as well
as shared tests, build, IPA packaging, and artifact publication. Keeping this green run
separate preserves the native rejection as a real failed result rather than masking it.
