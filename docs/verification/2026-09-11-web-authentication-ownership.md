# ASWebAuthenticationSession ownership verification

## Scope

D11 compares two Feature owners using the standard per-request `ASWebAuthenticationSession` boundary and adds only the missing host presentation arbitration and runtime ownership connection.

## Focused provider checks

`MiniAppWebAuthenticationTests` uses an injected session provider and no network:

- Feature A owns the admitted presentation; Feature B receives a conflict naming A and no second native session is created.
- A and B completions return only to their initiating Feature, and a late callback from an ended A request cannot reach B.
- request cancellation is idempotent, cancels its native session once, delivers cancellation once, and ignores a late native callback.
- native `start() == false` releases the surface and reports rejection before B retries.
- shutting down B's runtime cannot cancel A; shutting down A cancels A exactly once and closes later admission.
- an old Feature A connection/runtime cannot cancel a replacement A connection, and an old native callback stays ignored.
- separate coordinators model separate host presentation surfaces without interfering.
- a per-request provider remains alive during its active request and is released after completion.

The native adapter creates `ASWebAuthenticationSession`, assigns the supplied `presentationContextProvider` and ephemeral preference, and forwards the native callback/error. Compilation in the normal Xcode CI supplies the native API comparison; the provider suite supplies deterministic ownership evidence.

## Evidence boundary

The focused suite does not present the OS authentication UI and does not contact an OAuth provider. It therefore does not claim consent-sheet behavior, browser SSO behavior, registered callback routing, or successful external login. Those require a configured app/provider and device or Simulator UI verification.

The native adapter also accepts `ASWebAuthenticationSession.Callback`, including `.https(host:path:)`, on its native availability range. Compilation proves API availability and wiring only; it does not prove the associated-domain configuration or OS delivery of an HTTPS callback.

Run 34535983015, source `295b4252bdb9fced887971483ae6ec912842aa29`, compiled and launched the isolated native probe and exposed AuthenticationServices' browser sheet. Its first UI attempt failed because a meta refresh did not activate the custom scheme without a user gesture, and the cancel query matched both the fixture's launch button and the browser sheet's `Close` control. The retry uses an explicit local-page link and the browser control's accessibility identifier. This run does not count as successful native callback/cancel evidence.

Run 34535785062, source `7b71bc19f9767fc495b6f0a7756f44a930596259`, succeeded. The then-current 7 provider-injection tests passed, including same-Feature replacement connection isolation and separate-coordinator independence; the native `Callback` overload compiled in the generated app build.

Run 34537802126, source `aeeadc9d05a205d2affcbe935c05153eb435c5e8`, completed the first D11 native baseline step successfully on an iOS 26.5 Simulator. Both direct-Apple UI tests passed: the local HTTP page's `Return to App` link reached the registered custom callback, and the browser sheet's `Close` control produced `ASWebAuthenticationSessionError.canceledLogin`. No credentials or external OAuth service were used. The overall workflow later recorded five failed assertions across three generated-host UI tests and was ultimately marked cancelled; their cause was not determined in this D11 run, so they are not classified as pre-existing. The probe did not assert that an explicit consent prompt appeared, and HTTPS associated callback delivery remains untested.

Run 34534109606, source `27d6b186739ac06dc6be9e199fe290a3d29e8ba8`, stopped during shared-package compilation because the runtime extension and cleanup method are separate files while `close()` was declared `fileprivate`. The cleanup remains module-internal and is reverified after correcting that access level.

Run 34534363845, source `55d8c1aa795347f94611432b581cb44493e89077`, succeeded with Xcode 26.6. `MiniAppWebAuthenticationTests` executed all 5 provider-injection tests with 0 failures, the standard shared suite passed, and the generated native app built successfully with the AuthenticationServices adapter. No `MiniAppDefinition`, navigation, project-generation, or workflow change is part of this unit.
