# Notification UI regression verification (2026-09-11)

## Scope

CI run `34537802126` failed in
`GeneratedFeatureUITests.testNativeNotificationRequestPayloadsReachOnlyTheirOwners` while looking for the notification card's `View` / `表示` action after a left swipe.

## Evidence and cause

The same run first discovered and executed
`testNativeCustomActionReachesOwnerWithoutReplacingVisibleFeature` as an independent XCTest. That execution found and tapped `View` / `表示`, invoked the custom action, preserved lifecycle B as the visible feature, delivered `same-action` only to lifecycle A, and passed.

Immediately afterward XCTest executed the composite
`testNativeNotificationRequestPayloadsReachOnlyTheirOwners`, which directly called the foreground and custom-action test methods again. During this second custom-action execution, the notification card existed before the swipe, but the post-swipe accessibility hierarchy was the Home screen rather than Notification Center. Therefore `View` / `表示` was not available.

The regression was caused by helper scenarios retaining the `test` prefix: XCTest discovered them independently while the composite test also invoked them directly. This duplicated stateful SpringBoard notification interaction in one generated-host test run.

## Change

The two scenario methods are now private helpers named with a `verify` prefix. The single public composite test remains the XCTest entry point and still performs, in order:

1. foreground request content and owner isolation checks;
2. foreground notification removal;
3. custom action content, visible-feature preservation, and owner isolation checks.

No request-content, owner-isolation, or other-feature assertion was removed or relaxed.

## Focused CI

CI run `34543925004` passed. The generated-host log contains one discovered
notification test entry: `testNativeNotificationRequestPayloadsReachOnlyTheirOwners`,
which passed in 125.149 seconds. Neither former helper was discovered as an
independent test. The complete workflow also passed.
