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
