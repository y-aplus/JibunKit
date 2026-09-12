# Shared refresh native pending probe (2026-09-12)

## Scope

The existing `BackgroundTasksNative` fixture now contains a real-device diagnostic for the explicit shared app-refresh path. It does not alter `JibunKitCore`, the production app, or the existing direct wrapper/native comparison. The new shared identifier is declared only in the temporary fixture's permitted identifiers.

At app launch the fixture constructs one `MiniAppSharedRefreshCenter` with a journal under the fixture app's Application Support directory, creates stable A/B owner handles, registers both `sync` handlers before `ProbeView` is created, and reconciles recovered work. It does not create another center in the same process.

## Manual diagnostic contract

The prepare action clears only A/B logical requests and fixture-owned expectation/evidence files, then submits A and B with the same local `sync` identifier and different future earliest dates. It reports each durable generation separately from its native scheduling result. A pass requires:

- one logical pending generation for each owner;
- exactly one standard `BGAppRefreshTaskRequest` for the dedicated shared native identifier;
- the native earliest date equal to the minimum logical date;
- cancelling A to preserve B's exact generation and date; and
- the same single native request remaining at B's date.

The fixture stores B's expected generation/date outside the journal. After terminating and relaunching the app, the verify action compares that expectation with B recovered through the file journal and with exactly one standard pending native request. A native rejection never becomes a pass: the UI reports its error domain/code together with the durable A/B generations. Missing preparation, malformed state, and unavailable fixture handles are also explicit failures.

If iOS launches the native task independently, the registered owner handler records owner, generation, recovery status, and completion outcome in a separate evidence file. The prepare and verify buttons inspect scheduling state; they are not described as OS launch evidence. Cleanup cancels only this shared path's A/B pending requests and removes fixture expectation/evidence—it does not cancel the pre-existing direct/native identifiers.

## Verification status

The existing Simulator lane remains compile-only because native `BGTaskScheduler` runtime acceptance is unavailable there. It compiles the app and all UI tests but deliberately selects no successful runtime assertion for this new method. A real-device run and any user-facing device instructions remain parent-owned future work. Local Windows checks cannot compile Swift/Xcode; CI should first preserve the existing fixture build-only path and production regressions.
