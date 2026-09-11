# Notification UI regression verification (2026-09-11)

## Scope

CI run `34537802126` failed in
`GeneratedFeatureUITests.testNativeNotificationRequestPayloadsReachOnlyTheirOwners` while looking for the notification card's `View` / `表示` action after a left swipe.

## Evidence and remaining uncertainty

The same run first discovered and executed
`testNativeCustomActionReachesOwnerWithoutReplacingVisibleFeature` as an independent XCTest. That execution found and tapped `View` / `表示`, invoked the custom action, preserved lifecycle B as the visible feature, delivered `same-action` only to lifecycle A, and passed.

Immediately afterward XCTest executed the composite
`testNativeNotificationRequestPayloadsReachOnlyTheirOwners`, which directly called the foreground and custom-action test methods again. During this second custom-action execution, the notification card existed before the swipe, but the post-swipe accessibility hierarchy was the Home screen rather than Notification Center. Therefore `View` / `表示` was not available.

The helper scenarios retained the `test` prefix: XCTest discovered them independently while the composite test also invoked them directly. This duplicated stateful SpringBoard notification interaction in one generated-host test run. Duplication is established; its causal relationship to the second swipe closing Notification Center is not yet established. A focused run of the composite method alone also ran the scenarios only once before this rename, so its success cannot prove that the display failure has been resolved.

## Change

The two scenario methods are now private helpers named with a `verify` prefix. The single public composite test remains the XCTest entry point and still performs, in order:

1. foreground request content and owner isolation checks;
2. foreground notification removal;
3. custom action content, visible-feature preservation, and owner isolation checks.

No request-content, owner-isolation, or other-feature assertion was removed or relaxed.

## Focused CI

CI run [34543925004](https://github.com/y-aplus/JibunKit/actions/runs/34543925004), source `966d93a739d6d8a7bdb4539f1a89c0b8fbaad533`, passed. The generated-host log contains one discovered
notification test entry: `testNativeNotificationRequestPayloadsReachOnlyTheirOwners`,
which passed in 125.149 seconds. Neither former helper was discovered as an
independent test. The complete workflow also passed.

Shared tests: 167 passed. Normal host UI: 11 passed in 466.845 seconds. The separate Files selected-Counter restore passed in 154.300 seconds. Records' two tests passed with the known Simulator Quick Look expected failure. This is not a full generated-host suite pass. A deliberate two-cycle notification regression remains to check whether cleanup, recreation, and the OS action UI work repeatedly without reducing the semantic assertions.
