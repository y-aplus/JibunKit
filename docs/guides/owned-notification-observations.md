# Feature-owned NotificationCenter observations

Create one observation collection from each `MiniAppRuntime`. The runtime owns
its cancellation boundary, while `NotificationCenter` still performs native
notification-name and sender-object filtering.

```swift
@MainActor
final class FeatureModel {
    private let runtime = MiniAppRuntime()
    private lazy var notifications = try! runtime.makeNotificationObservations()

    func start(sender: NSObject) throws {
        try notifications.observe(
            name: .featureDidChange,
            object: sender,
            extract: { note in note.userInfo?["count"] as? Int }
        ) { [weak self] count in
            self?.apply(count)
        }
    }

    func stop() async {
        await runtime.shutdown()
    }
}
```

The extractor runs synchronously on the notification's posting thread. It must
produce a `Sendable` value; only that value crosses to the main actor. Do not
capture UI or main-actor state in the extractor. The receiver always runs on
the main actor.

Keep the returned `MiniAppNotificationObservation` when one registration needs
to end earlier than its owning Feature, and call `cancel()`. Calling
`cancelAll()`, releasing the collection, or awaiting `runtime.shutdown()`
removes each native observer explicitly. Values already waiting for main-actor
delivery are discarded after cancellation. Cancellation also releases the
receiver closure even while its owner collection remains alive. A receiver
that has already begun is allowed to finish, so keep receiver work short and
use runtime-owned tasks for asynchronous work.

An observation collection is single-use after `cancelAll()`. Create a new
runtime and collection when restarting a Feature.
