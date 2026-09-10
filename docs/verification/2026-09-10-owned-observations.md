# D02 owned NotificationCenter observations

Date: 2026-09-10

## Boundary and contract

Independent apps lose all process-local `NotificationCenter` registrations
when their process ends. Multiple Features integrated into one process do not
have that boundary, so a stopped Feature can otherwise remain subscribed and
react to events intended for a live Feature.

`MiniAppNotificationObservations` restores an explicit owner boundary. Each
Feature obtains a collection from its `MiniAppRuntime`; stopping that runtime
removes only the registrations in that collection. Each registration also has
an idempotent cancellation token for an earlier, narrower lifetime.

The implementation passes `name` and `object` directly to
`NotificationCenter.addObserver(forName:object:queue:using:)`. It registers
with a nil operation queue, extracts a typed `Sendable` value on the posting
thread, and moves that value to a main-actor receiver. A lock-protected active
flag is checked before extraction and when the main actor claims the receiver.
Owner cancellation on the main actor suppresses pending main-actor deliveries.
Concurrent individual cancellation has a narrower guarantee: a receiver already
claimed by the main actor may run even if invocation follows cancellation.
Runtime shutdown registers native observer removal in its awaited cleanup
sequence.

Apple documents that a non-nil object restricts delivery to notifications from
that sender, a nil queue invokes the block synchronously on the posting thread,
the center holds the block until removal, and block observers should be removed
explicitly. Source:
https://developer.apple.com/documentation/Foundation/NotificationCenter/addObserver%28forName%3Aobject%3Aqueue%3Ausing%3A%29

## Focused evidence

`MiniAppNotificationObservationsTests` covers:

- two real `NotificationCenter` owners observing the same name, then cancelling
  one while the other continues;
- native name and sender-object filtering;
- suppression of a value queued before owner cancellation;
- release of a receiver captured by an individually cancelled registration,
  and synchronous removal of that token from an owner collection that remains
  usable;
- collection deinitialization removing its native observer and releasing the
  receiver;
- a reentrant post and ordered main-actor delivery;
- background-thread extraction followed by main-actor delivery;
- awaited `MiniAppRuntime.shutdown()` removing one owner's native observers
  without affecting another runtime.

The tests use fulfilled and inverted XCTest expectations for delivery
boundaries; they do not infer completion from a fixed number of executor
yields. Local execution is unavailable on the Windows development host because
the package requires Swift/Xcode. The pre-review GitHub Actions run
[34481904178](https://github.com/y-aplus/JibunKit/actions/runs/34481904178)
succeeded on Xcode 26.6. Its `Test shared feature logic` step compiled the new
implementation under Swift 6 and ran all eight
`MiniAppNotificationObservationsTests` with zero failures. The same run also
passed the independent Feature package tests, the release iOS build, and IPA
packaging. Simulator tests were intentionally disabled because this boundary
uses Foundation only and the real `NotificationCenter` cases ran on macOS.

## Remaining limits

Concurrent individual cancellation cannot retract a receiver already claimed
by the main actor, even if the call itself has not begun when cancellation
returns. Main-actor owner cancellation does not have that race.
Foundation notification posting is synchronous only through extraction; the
main-actor receiver is intentionally asynchronous. This API does not isolate
global observers registered directly by Feature code, distributed
notifications, notification ordering across unrelated posting threads, or
resource work started outside the owning runtime.
