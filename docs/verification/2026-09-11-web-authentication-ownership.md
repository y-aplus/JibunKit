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

The native adapter creates `ASWebAuthenticationSession`, assigns the supplied `presentationContextProvider` and ephemeral preference, and forwards the native callback/error. Compilation in the normal Xcode CI supplies the native API comparison; the provider suite supplies deterministic ownership evidence.

## Evidence boundary

The focused suite does not present the OS authentication UI and does not contact an OAuth provider. It therefore does not claim consent-sheet behavior, browser SSO behavior, registered callback routing, or successful external login. Those require a configured app/provider and device or Simulator UI verification.

Run 34534109606, source `27d6b186739ac06dc6be9e199fe290a3d29e8ba8`, stopped during shared-package compilation because the runtime extension and cleanup method are separate files while `close()` was declared `fileprivate`. The cleanup remains module-internal and is reverified after correcting that access level.

Run 34534363845, source `55d8c1aa795347f94611432b581cb44493e89077`, succeeded with Xcode 26.6. `MiniAppWebAuthenticationTests` executed all 5 provider-injection tests with 0 failures, the standard shared suite passed, and the generated native app built successfully with the AuthenticationServices adapter. No `MiniAppDefinition`, navigation, project-generation, or workflow change is part of this unit.
