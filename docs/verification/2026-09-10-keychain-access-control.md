# D08 Keychain access control verification

Date: 2026-09-10

## Boundary and implementation

`MiniAppKeychain` now accepts native `SecAccessControl` protection and a
caller-owned `LAContext` per `data`, `set`, and removal operation. It does not
cache or share authentication state. `set` continues to use `SecItemUpdate`
first and never deletes an item to change its value or protection. Omitting
protection attributes therefore preserves an existing item's policy; supplying
both a standalone accessibility and an access control fails with `errSecParam`.

Service, Feature, account, synchronizable, and access-group clauses remain the
same in every query, including authenticated removal.

Apple documents that `SecAccessControlCreateWithFlags` combines accessibility
with user-presence conditions, and that callers need not also set
`kSecAttrAccessible`. Apple also documents `kSecUseAuthenticationContext` as a
caller-supplied reusable `LAContext`; without one Security creates and discards
its own context. Setting `LAContext.interactionNotAllowed` prevents interactive
authentication. Sources:

- https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility
- https://developer.apple.com/documentation/security/ksecuseauthenticationcontext
- https://developer.apple.com/documentation/localauthentication/lacontext/interactionnotallowed

## Focused evidence

`MiniAppKeychainAccessControlTests` uses native Security APIs to cover:

- creation with a native access-control object and preservation of its embedded
  accessibility across a data-only update;
- rejection of ambiguous access-control plus accessibility without creating an
  item;
- non-interactive failure when updating a user-presence-protected item;
- existence of the protected item after that failed in-place update;
- continued readability of the same account owned by another Feature.
- distinct caller-owned contexts used for native save/read/removal operations,
  with removal still limited to one Feature owner.

Initial macOS CI run
[34486251417](https://github.com/y-aplus/JibunKit/actions/runs/34486251417)
compiled the implementation but returned `errSecMissingEntitlement` when its
unsigned test host attempted to add both access-controlled items. The tests now
skip only that OS/environment condition rather than treating macOS as biometric
evidence. Context propagation and owner scoping still run against the native
macOS Keychain without access-control protection.

Revised GitHub Actions run
[34486755340](https://github.com/y-aplus/JibunKit/actions/runs/34486755340)
succeeded on Xcode 26.6. `MiniAppKeychainAccessControlTests` executed four
tests with zero failures: the context/ownership and invalid-combination tests
passed, while the two protected-item cases reported the documented
`errSecMissingEntitlement` skip. The complete shared suite executed 127 tests
with those same two skips and zero failures. Independent Feature package tests,
the release iOS build, and IPA packaging also succeeded. Existing cookie and
password stores exercised their unchanged default Keychain path in the shared
suite.

## Unverified OS-dependent behavior

The unsigned macOS CI host cannot add an access-controlled item and therefore
cannot exercise its prohibited-UI failure or establish successful Face ID or
Touch ID authentication. A signed Simulator or device test remains necessary
for protected-item persistence, failed-update retention, prompt text, user
approval, cancellation UI, passcode/enrollment changes, biometric-set
invalidation, background/locked-device behavior, and host `Info.plist`
integration. No test bypasses or simulates OS consent.

## Prepared signed-iOS probe

`Tests/TemplateIntegration/KeychainAccessControlProbe.swift` provides
`KeychainAccessControlProbe.definition`. After the fixture is copied into the
temporary host, register it by adding exactly this entry to the array passed to
`MiniAppRegistry.makeRegistry`:

```swift
KeychainAccessControlProbe.definition,
```

Copy `Tests/TemplateIntegration/KeychainAccessControlUITests.swift` into the
temporary UI-test target and select
`KeychainAccessControlUITests/testProtectedOperationsMatchNativeBaselineAndPreserveBothOwners`.
The probe uses a caller-owned non-interactive context and reports separate
diagnostics rather than silently skipping. It first requires protected reads to
fail without interaction. It then compares JibunKit's data-only update with a
direct `SecItemUpdate` baseline: native success is accepted, while native
rejection must leave modification dates unchanged. Both paths must retain
protected-read enforcement, both items, and an unchanged second owner.
