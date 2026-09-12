# Shared refresh native pending probe (2026-09-12)

## Scope

The existing `BackgroundTasksNative` fixture now contains a real-device diagnostic for the explicit shared app-refresh path. It does not alter `JibunKitCore`, the production app, or the existing direct wrapper/native comparison. The new shared identifier is declared only in the temporary fixture's permitted identifiers.

At app launch the fixture constructs one `MiniAppSharedRefreshCenter` with a journal under the fixture app's Application Support directory, creates stable A/B owner handles, registers both `sync` handlers before `ProbeView` is created, and reconciles recovered work. It does not create another center in the same process.

## Manual diagnostic contract

The prepare action clears only A/B logical requests and fixture-owned expectation/evidence files, then submits A first at 30 minutes and B second at 60 minutes with the same local `sync` identifier. It reports each durable generation separately from its native scheduling result. A pass requires:

- one logical pending generation for each owner;
- exactly one standard `BGAppRefreshTaskRequest` for the dedicated shared native identifier;
- the native earliest date remaining at A's earlier date after B is submitted;
- cancelling A to preserve B's exact generation and date; and
- the same single native request being resubmitted at B's later date.

The fixture stores B's expected generation/date and the current launch UUID outside the journal. After terminating and relaunching the app, the verify action requires a different launch UUID, then compares that expectation with B recovered through the file journal and with exactly one standard pending native request. This prevents repeated buttons in one process from being labeled as restart recovery. A native rejection never becomes a pass: the UI reports its error domain/code together with the durable A/B generations. Missing preparation, malformed state, and unavailable fixture handles are also explicit failures.

If iOS launches the native task independently, the registered owner handler first appends owner, generation, receipt time, recovery status, and completion intent to a separate evidence file. Only then does it complete the logical execution; recording the returned acknowledgement is a distinct best-effort update, so an entry with a pending result is not claimed as confirmed completion. Missing evidence means no event, while corrupt/unreadable evidence is an explicit read failure and its bytes are not replaced with an empty history. The prepare and verify buttons inspect scheduling state; they are not described as OS launch evidence. Cleanup cancels only this shared path's A/B pending requests, verifies logical counts and the shared native pending count are zero, and then removes fixture expectation/evidence—it does not cancel the pre-existing direct/native identifiers.

All fixture actions share one busy state, preventing direct comparison, prepare, verify, and cleanup tasks from interleaving across suspension points. The diagnostic content is scrollable so long generation/error output does not push controls out of reach.

## Verification status

The existing Simulator lane remains compile-only because native `BGTaskScheduler` runtime acceptance is unavailable there. It compiles the app and all UI tests but deliberately selects no successful runtime assertion for this new method. A real-device run and any user-facing device instructions remain parent-owned future work. Local Windows checks cannot compile Swift/Xcode; CI should first preserve the existing fixture build-only path and production regressions.

Run [34684495878](https://github.com/y-aplus/JibunKit/actions/runs/34684495878) succeeded at source `85ccd1968370014e57e31b33d2769e1407b052d3`. The existing injected-scheduler iOS target ran all 16 shared refresh journal/center tests with zero failures in 0.048 seconds. The native fixture, including the new real-device UI method, reported `TEST BUILD SUCCEEDED`; the runner explicitly reported that native scheduler runtime validation was not executed. The focused production mini-app Search regression passed in 78.396 seconds. Because this was a focused compile verification for fixture-only changes, the normal IPA build and unrelated UI/Files tests were intentionally skipped.

This run establishes Swift 6/iOS compilation of the launch registration, busy UI, restart identity check, standard pending-request inspection, cleanup verification, and evidence persistence code. It does not establish real `BGTaskScheduler` acceptance, a pending count/date on a device, an app relaunch recovery result, an OS-delivered launch, or expiration delivery. Those remain real-device evidence only.
