# WebKit persistent storage ownership

Create every `WKWebView` with the Feature's data store before loading a page:

```swift
let configuration = WKWebViewConfiguration()
configuration.websiteDataStore = context.websiteDataStore(profile: "account-1")
let webView = WKWebView(frame: .zero, configuration: configuration)
```

The returned store is Apple's persistent `WKWebsiteDataStore`, identified by a
stable UUID derived from the Feature ID and profile. Two Features can therefore
use the same web origin, cookie name, and `localStorage` key without sharing
values. The same boundary applies to IndexedDB database, object-store, and key
names. Reuse the same profile for later launches that should reopen the same
website state. Changing the derivation or profile loses that association and
requires an explicit migration plan.

The host observes page operations through asynchronous JavaScript evaluation.
Treat `WKNavigationDelegate.webView(_:didFinish:)` plus an application-level
JavaScript acknowledgement as the execution completion boundary;
an arbitrary delay does not prove that a page loaded or that its write ran.
For IndexedDB, resolve that acknowledgement from the transaction's
`oncomplete`, not merely from the `put()` request callback. Close database
connections after the transaction so later deletion cannot be blocked.
Before process termination, allow the app to enter its normal background state.
That acknowledgement is not a durable-flush guarantee. WebKit controls the
durable flush timing, and JibunKit does not call private
flush APIs.

To clear one owner's web state, call `removeData(ofTypes:modifiedSince:)` on that
owner's store and await completion. Include every data type the product promises
to clear—for example Cookies, local storage, and IndexedDB databases—rather than
assuming one type removes another. Do not clear `WKWebsiteDataStore.default()`
or enumerate unrelated identifiers as a substitute. Existing WebViews using a
store must be coordinated by the Feature before deletion; automatic lifetime
coordination is not currently provided by the store factory. In a managed
Feature, keep the `WKWebView` and store in the Feature object, attach it to
`MiniAppFeatureLifetime`, and perform each page read/write inside
`MiniAppRestoreCoordinator.withStoreAccess(for:operation:)`. Register a
`MiniAppRemovalProvider` which calls `removeData` directly on the already
reserved owner's store. The removal callback must not re-enter store access:
`MiniAppManagement` closes admission and drains the lifetime first, then holds
the exclusive reservation across unregister and removal. Draining first allows
in-flight page operations to finish and release their ordinary reservations.

Cancellation is cooperative. Runtime stop closes admission, cancels its owned
task, and waits for the page operation to return before cleanup. Check task
cancellation before admitting a write; JavaScript that has already begun may
still finish in WebKit. A cancelled Swift task is therefore not proof that a
WebKit transaction was rolled back.

For a deliberate pre-commit hold, acquire ordinary store access first, then
publish the waiting state and suspend on a Feature-owned continuation. It must
be resumed exactly once by an explicit release or task cancellation; do not use
a wall-clock delay as evidence that management encountered an in-flight writer.
Once `callAsyncJavaScript` has returned its page acknowledgement, preserve that
successful result rather than rewriting it to cancellation because the task was
cancelled later.

When checking that an IndexedDB database was deleted, do not call
`indexedDB.open(name)` first: opening a missing database creates it. Check
`indexedDB.databases()` for absence, and only open a database already reported
as present.

This isolates WebKit website data, not server accounts or tracking performed
outside the store. Cookie rules such as `Secure`, `SameSite`, domain, and path
remain WebKit behavior.

The candidate's storage persistence, explicit cancellation, and management
drain/removal methods passed in run34819734774, using the embedded loopback
fixture and normal Feature entrypoints. The same run failed during Spotlight
unregister in the first disable test; the next authentication test inherited
that incomplete management state. Storage method passes do not establish that
the complete management path is ready. The earlier four-method pass in the
cancelled run34808525786 remains historical evidence. P1-B is unreleased and
physical-device checks remain; see [P1-B verification](../verification/2026-09-14-p1-b.md).
