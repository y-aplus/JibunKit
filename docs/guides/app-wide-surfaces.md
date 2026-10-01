# App-wide system surfaces

iOS treats some surfaces as one per app: the Home Screen quick action menu, the icon badge, continued user activities, TipKit's configuration, and the notification Service and Content extensions. Inside JibunKit several Features share that one app, so the host owns each surface and hands every Feature only its own part. None of these is required; add only what a Feature uses.

These are cooperative ownership boundaries, not a security sandbox. Unit tests cover owner selection and aggregation; long-press menus, badges, Handoff and notification extensions still need to be checked on a device.

## Home Screen quick actions

The host publishes up to four items. Recently opened Features come first, then the remaining enabled Features in registration order. Each Feature gets one item before any Feature gets a second.

A Feature that declares nothing gets one item that opens its root. To choose the items, pass `quickActions`:

```swift
MiniAppDefinition(
    id: MiniAppID("zaiko"), title: "Stock", systemImage: "shippingbox",
    appendDestination: { destination, path in
        guard destination == "low-stock" else { return false }
        path.append(StockDestination.lowStock)
        return true
    },
    quickActions: [
        MiniAppQuickAction(title: "Low stock", systemImage: "exclamationmark.triangle", destination: "low-stock"),
    ]
) { _ in StockRootView() }
```

A destination goes through the Feature's `appendDestination`, like a URL or Spotlight route; `nil` opens the root. Destinations require `appendDestination`. Disabled Features and Features that failed launch preparation never appear. The host installs a small window scene delegate to receive items while the app runs; SwiftUI keeps owning the windows.

## Icon badge

Set only your Feature's count:

```swift
try await context.setBadgeCount(lowStockItems.count)
```

The icon shows the sum over enabled Features. Disabling or deleting a Feature clears its count. Do not set `UNNotificationContent.badge` or call `setBadgeCount` on `UNUserNotificationCenter` directly: either replaces every Feature's count. Counts change only while JibunKit runs; a notification delivered to a stopped app cannot add to them.

## Handoff and other user activities

A Feature that continues its own `NSUserActivity` types declares them once:

```swift
userActivity: MiniAppUserActivityHandler(activityTypes: ["com.example.notes.view"]) { activity in
    (activity.userInfo?["id"] as? String).map { .detail($0) } ?? .root
}
```

Also declare the same types in the app target's `NSUserActivityTypes` build requirement. The resolver only reads the activity; the host opens the result through `appendDestination` in the scene that received it. Each type must belong to exactly one Feature, and Spotlight's result and query types stay with the host; the host stops at launch if these rules are broken. Creating an activity (for example with SwiftUI's `userActivity(_:element:_:)`) remains Feature code.

## TipKit

The host calls `Tips.configure()` once at launch. Features declare and show tips but never call `configure` or `resetDatastore`. Give each tip an `id` that includes the Feature ID, because type names can repeat across packages. TipKit cannot forget one Feature's tip history, so it remains after that Feature is deleted.

## Notification Service and Content extensions

An app has at most one of each. JibunKit does not build them by default, because each extension uses another App ID when signing (a real limit with free accounts). When a Feature needs one:

1. Set `EnabledFeatureBuildRequirements.notificationService` or `notificationContent` in `Tuist/ProjectDescriptionHelpers`. For content, list every category identifier the extension displays, as returned by `MiniAppContext.notificationCategoryIdentifier(for:)` (for example owner `a.b` and key `x` give `jibunkit.a%2Eb.category.eA==`).
2. Add the Feature's package product to that extension target in `Project.swift`.
3. Return the Feature's handler from `NotificationService.makeHandlers()`, or its view controller from `NotificationContentViewController.makeContentViewController(for:)`.

The host chooses the owner from the payload's `JibunKitMiniAppID` when present, and never falls back to identifier matching if that owner has no handler. Otherwise the request or category identifier must match exactly one Feature's namespace. A notification without an owning handler is shown unchanged; in the content extension, the custom area collapses and only the system title and body remain. Notification actions are not handled inside the content extension: the system forwards them to the app, where `onNotificationAction` receives them. A service handler follows `UNNotificationServiceExtension`'s contract: call the content handler exactly once and deliver the best content when time expires.

The default CI does not build these optional targets. The **Build optional extensions** workflow compiles the host with both enabled (with empty handler lists) and checks that they are embedded; it does not exercise notification delivery.
