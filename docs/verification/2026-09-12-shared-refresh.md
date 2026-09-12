# Shared background refresh

Status: implementation and scoped CI verified. This is not D15 completion or
evidence of an OS-delivered launch.

## Contract and implementation

[The coordination contract](../background-refresh-coordination.md) describes the
one-slot difference introduced by integrating independent apps. The implementation
adds an explicit shared refresh path; the existing direct BackgroundTasks API is
unchanged. Processing requests are not collapsed into a refresh request.

The journal stores owner, local identifier, generation, earliest date, and phase.
Submitting the same owner/local ID replaces only its pending generation. A running
or recovered generation survives new submissions. Unknown handlers remain durable
without being dispatched to another owner. Journal acceptance and OS acceptance
are returned separately.

Native launch fixes a batch of due jobs and their handlers after saving the running
generations. Each logical execution owns its cleanup; the native batch completes
once after every execution finishes. Expiration, unregistering, pending cancellation,
and completion do not silently end another Feature's work. A failed acknowledgement
reports failure and preserves recoverability; redelivery requires Feature idempotence.

## Review and local checks

The parent implemented center/batch/native connection and integration tests; the
Sol low worker implemented the journal and reviewed the center once before CI.
Review caught two false-success risks and fixed them before dispatch:

- File existence checks could hide unreadable journals. Load now reads directly
  and returns empty only for an explicit missing-file error, preserving other errors.
- The scheduler spy could launch without a submitted request. Launch now requires
  both a pending request and a registered handler, so missing reconciliation fails.

The parent also reviewed persistence/center connection, native adapter, iOS test
target, and method-by-method result guards. Python syntax, existing Python tests,
and whitespace checks passed on Windows. Swift compilation and runtime tests were
not run locally because this environment has no Swift/Xcode toolchain.

## CI scope

- All existing shared Swift tests, including six journal and ten center/batch tests.
- The same 16 new tests on iOS Simulator, including actual-file save/load and
  restart from a snapshot of durable bytes. The scheduler and expiration are injected.
- Native BackgroundTasks fixture build only, production app/Widget/IPA build, and
  the focused mini-app Search UI regression.

The existing BackgroundTasks validation flag runs the shared-refresh iOS XCTest
target before the native comparison. Its compile-only option suppresses the native
scheduler runtime comparison, not these unit tests. Each method must report passed;
runner success with zero tests is rejected. Logs and a dedicated `SharedRefresh.xcresult`
are uploaded with BackgroundTasks diagnostics.

## Verified result

Run [34683036628](https://github.com/y-aplus/JibunKit/actions/runs/34683036628) succeeded
at source `186aff03cb0a4f3a64ada36223a31df9cd7966c3`.

- Shared Swift tests: 203 tests, two existing skips, zero failures (3.468 seconds).
- iOS shared refresh tests: all six journal and ten center/batch methods passed,
  zero failures (0.166 seconds). This includes actual-file restart snapshots,
  malformed-path read rejection, corruption/invalid-save preservation, one-slot
  scheduling, pending cancellation, native rejection, expiry/cleanup retention,
  reentrant launch, generation replacement, and failed acknowledgement recovery.
- Native BackgroundTasks fixture: `TEST BUILD SUCCEEDED`; runtime comparison was
  explicitly not executed. The step name alone is not proof of native acceptance.
- Production app/Widget/IPA and native build-requirement checks passed.
- Search UI regression passed in 45.659 seconds. Full UI/Files regression was not
  selected for this additive API, which existing Features do not call yet.

Real native pending-slot acceptance, cancellation retaining another owner, OS launch,
and expiration delivery remain separate verification work. This checkpoint does not
add a product UI probe or ask the user for a device check.
