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

CI results are recorded after the branch run.

## Unverified OS-dependent behavior

The macOS CI test can exercise native access-control storage and a prohibited-UI
failure, but it cannot establish successful Face ID or Touch ID authentication.
Simulator or device work remains necessary for prompt text, user approval,
cancellation UI, passcode/enrollment changes, biometric-set invalidation,
background/locked-device behavior, and host `Info.plist` integration. No test
bypasses or simulates OS consent.
