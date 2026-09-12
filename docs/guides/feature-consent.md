# Feature consent declarations

Use `MiniAppPermissionDeclaration` to give the host stable text for each
Feature-level permission. The declaration contains a stable permission ID, a
title, the reason the Feature wants the capability, and what remains available
when the user refuses it.

```swift
let reminders = MiniAppPermissionDeclaration(
    id: "notifications.reminders",
    title: "Reminder notifications",
    purpose: "Notify you when a reminder is due.",
    deniedBehavior: "Reminders remain available without alerts."
)
```

Keep the ID stable across releases and write the purpose and denied behavior in
terms the user can act on. Changing display text does not change an existing
decision; changing the ID represents a new permission which starts as
`.notDetermined`.

The host explicitly injects its `UserDefaults` domain into
`MiniAppConsentStore`. Decisions are stored separately for every Feature ID and
permission ID and can be `.notDetermined`, `.allowed`, or `.denied`.

```swift
let consentStore = MiniAppConsentStore(defaults: sharedDefaults)
let decision = consentStore.consent(
    for: MiniAppID("reminder"),
    permissionID: reminders.id
)
```

Removing or re-registering a Feature must call `removeConsents(for:)` so it
returns to an unconfirmed state without changing another Feature's decisions.
Saving `.notDetermined` or calling `removeConsent` removes an individual saved
answer.

This store records consent for JibunKit's Feature UI only. It does not request,
grant, revoke, or mirror operating-system permission state, and its namespacing
is not a security boundary between code running in the same process. The host
must still use the relevant system API when an OS permission is required.
