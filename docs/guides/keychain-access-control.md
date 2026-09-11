# Keychain access control and authentication context

`MiniAppKeychain` accepts a native `SecAccessControl` when an item needs more
than the default unlocked-device protection. Create it with Apple's
`SecAccessControlCreateWithFlags` API and pass it only when creating or
intentionally changing protection:

```swift
import LocalAuthentication
import Security

var error: Unmanaged<CFError>?
let access = SecAccessControlCreateWithFlags(
    nil,
    kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
    .userPresence,
    &error
)!
try keychain.set(secret, for: account, accessControl: access)
```

Do not also pass `accessibility`; a `SecAccessControl` already contains that
condition and the API rejects the ambiguous combination. Omitting both values
on a later `set` updates data in place and preserves the item's existing
protection. JibunKit never falls back to delete-and-reinsert when authentication
fails, so the old item is not discarded during a failed update.

For an operation on a protected item, pass a caller-owned `LAContext`:

```swift
let authentication = LAContext()
authentication.localizedReason = "Use the saved account"
let secret = try keychain.data(
    for: account,
    authenticationContext: authentication
)
```

The context is attached only to that Security operation. JibunKit neither
stores it nor shares a process-wide context. The caller controls reuse,
localized prompt text, invalidation, and interaction policy. For work that must
not show UI, set `interactionNotAllowed = true`; an item requiring authentication
then fails instead of presenting a prompt. Treat cancellation and other
authentication errors as operation failures and leave the existing item intact.

The same optional context is available to `set`, `remove(account:)`, and
`removeAll()`. Namespace queries remain restricted to the Feature, service,
account, and optional access group; access control never broadens deletion.

Face ID use requires the host application's `NSFaceIDUsageDescription`.
Availability and successful authentication depend on the device, passcode,
enrollment, entitlements, and current OS state, so handle returned Security
errors rather than assuming a prompt can succeed.
