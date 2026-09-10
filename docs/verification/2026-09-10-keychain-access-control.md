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
macOS Keychain without access-control protection. Final CI status is recorded
after the revised branch run.

## Unverified OS-dependent behavior

The unsigned macOS CI host cannot add an access-controlled item and therefore
cannot exercise its prohibited-UI failure or establish successful Face ID or
Touch ID authentication. A signed Simulator or device test remains necessary
for protected-item persistence, failed-update retention, prompt text, user
approval, cancellation UI, passcode/enrollment changes, biometric-set
invalidation, background/locked-device behavior, and host `Info.plist`
integration. No test bypasses or simulates OS consent.
