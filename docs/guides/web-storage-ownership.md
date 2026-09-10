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
values. Reuse the same profile for later launches that should reopen the same
website state. Changing the derivation or profile loses that association and
requires an explicit migration plan.

Page writes are asynchronous. Treat `WKNavigationDelegate.webView(_:didFinish:)`
plus an application-level JavaScript acknowledgement as the completion boundary;
an arbitrary delay does not prove that a page loaded or that its write ran.
Before process termination, allow the app to enter its normal background state.
WebKit controls the durable flush timing, and JibunKit does not call private
flush APIs.

To clear one owner's web state, call `removeData(ofTypes:modifiedSince:)` on that
owner's store and await completion. Do not clear `WKWebsiteDataStore.default()`
or enumerate unrelated identifiers as a substitute. Existing WebViews using a
store must be coordinated by the Feature before deletion; automatic lifetime
coordination is not currently provided.

This isolates WebKit website data, not server accounts or tracking performed
outside the store. Cookie rules such as `Secure`, `SameSite`, domain, and path
remain WebKit behavior.
