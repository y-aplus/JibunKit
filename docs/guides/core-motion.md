# Motion activity and sensors

## Current integration contract

JibunKit has no API for Apple's Core Motion framework. A Feature imports it and creates its own managers. This guide covers the motion activity history (`CMMotionActivityManager`) that a derived host's Feature uses, and what is known about the other managers.

A shared host API is not needed for the activity history. A query runs on the manager that made it, and nothing it does changes another Feature's queries; unlike [location](location.md) geofences, there is no app-wide limit to share. What Features do share is the app's **Motion & Fitness** authorization, as described [below](#check-feature-consent-before-the-first-query).

### Check Feature consent before the first query

Declare a Feature permission such as `MiniAppPermissionDeclaration(id: "motion", ...)` and query only while its consent is `.allowed` ([consent](feature-consent.md)). Objects created with the definition can read it with `MiniAppConsentSource.isAllowed("motion")` ([capture](capture.md) shows how to connect it). A query started outside the Feature's screens, for example after a location event relaunched the app, must check the consent there as well.

The first query asks for the Motion & Fitness authorization. iOS keeps one authorization for the whole app, so once any Feature has it, another Feature's first query no longer asks. Read `CMMotionActivityManager.authorizationStatus()` before querying: when it is `.denied` or `.restricted`, do not query, and show the Feature's own message with a way to the Settings app. The host's management screen shows Feature consent only, not this authorization.

### Usage description

Add `NSMotionUsageDescription` to the `app.infoPlist` of `JibunKitFeature.json`, and its translations to `app.localizedInfoPlist` ([adding a feature](../mini-apps.md#2-connect-it-to-the-host)). The app has one value for the key. When another Feature already declares a different text, composing the build requirements stops, and the host writes the agreed text in `infoPlistResolutions` and `localizedInfoPlistResolutions` ([build requirements](feature-build-requirements.md)).

### Query history instead of keeping updates running

`queryActivityStarting(from:to:to:)` returns up to the last seven days, which iOS records whether or not the app runs. A Feature that needs past activity, such as when a ride ended, can query it when it needs it and save only the result, instead of running `startActivityUpdates` and storing every change. Saved results are Feature data: use owner-scoped storage and a [removal provider](feature-data-removal.md).

Updates that must continue after the screen changes belong to the [Feature lifetime](feature-lifetime.md): stop them when the Feature stops.

A derived host's Feature found that a query whose range has no activity at all fails with `CMErrorUnknown`, and treats it as an empty result. This has not been checked in this repository.

### Raw sensors

Apple asks an app to create only one `CMMotionManager`, because several instances can change the rate at which the accelerometer and gyroscope deliver data. JibunKit has no shared `CMMotionManager`, so two Features that each create one in the same host may receive data at another rate than they asked for. This has not been tested and is recorded in the [coexistence ledger](../coexistence-ledger.md) (D42). Until it is checked, a Feature should stop its updates when it leaves the screen, so that two Features rarely run them at once.

### Tests

Keep the Core Motion calls in one file wrapped in `#if os(iOS)`, and convert activities to the Feature's own plain Swift types before any logic uses them. CI runs Feature package tests on macOS ([why](../mini-apps.md#your-package-is-also-built-for-macos)), so test the logic there and check queries on a device: the Simulator has no motion activity.
