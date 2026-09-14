# Feature HTTP ownership

Each Feature owns its `URLSession` configuration and retains its cookie store,
password credential store, cache, session, and lifetime for as long as the
Feature is running. Do not use `HTTPCookieStorage.shared`,
`URLCredentialStorage.shared`, or `URLCache.shared` for Feature traffic.

```swift
let context = MiniAppContext(id: id)
let cookies = try MiniAppCookieStore(context: context, profile: "default")
let passwords = try MiniAppPasswordCredentialStore(context: context, profile: "default")
let cache = try context.urlCache(
    memoryCapacity: 1_048_576,
    diskCapacity: 4_194_304,
    containerURL: applicationContainer
)
let configuration = URLSessionConfiguration.default
configuration.httpCookieStorage = cookies.storage
configuration.urlCredentialStorage = passwords.storage
configuration.urlCache = cache
let session = URLSession(configuration: configuration)
```

The custom `URLCache` has an owner/profile disk directory. It supports evidence
that a reconstructed session can read a response without network access; it is
not a durability contract across process termination, OS cache eviction, an IPA
replacement, or a signing update. Persist login state through the cookie and
password stores instead.

Use fixed application-owned credentials or credentials entered by the user;
never put real credentials in fixtures or logs. `MiniAppPasswordCredentialStore`
persists password credentials only. Client identities, trust decisions, OAuth,
and other authentication schemes need their own explicit design.

## Operation and shutdown order

Run every ordinary operation through
`MiniAppRestoreCoordinator.withStoreAccess(for:)`, and register the operation
with the Feature's `MiniAppRuntime`. Keep the reservation until the network
operation and its persistence acknowledgement have both finished. Cancellation
and transport errors are failures, not empty successful responses.

For logout or management deletion:

1. Close admission to new Feature work.
2. Cancel and drain runtime-owned requests.
3. Perform server logout with the owner's private cookie store if required.
4. Persist the server's cookie deletion, then clear the owner's password store.
5. For management deletion, clear only that owner's cookie, credential, and cache data.

The management removal callback already has the owner's exclusive reservation;
it must not re-enter `withStoreAccess`. Deletion must be idempotent. Never seed
credentials or cookies merely because a view or process starts, since that would
recreate data after management deletion.

A feature-specific logout controller that runs after `lifetime.stop()` is
external to that stopped runtime, so retain and serialize it explicitly with
startup/writer controls. It must first await all runtime writers, then use one
ordinary StoreAccess reservation for logout. Current Core has no public
"stopped control lease" that also blocks a new `MiniAppFeatureLifetime.start()`;
candidate hosts must not treat a visible stopped-state resume button as proof
that external logout has completed. A reusable product solution would need a
Core-owned lease which makes start join/reject until the external control action
releases it, without changing management's own admission state.

Persist only after a successful response. If validation or persistence fails,
retain the prior durable snapshot and report failure. `MiniAppCookieStore.clear`
and `MiniAppPasswordCredentialStore.clear` deliberately delete persistent data
before changing the live store, so a Keychain deletion failure does not pretend
that logout succeeded.

Cookie and password snapshots are separate Keychain records. They do not form a
multi-store transaction: if one real save succeeds and the next fails, recovery
must report a partial commit rather than claim atomicity. The P1 probe's
injected failure is deliberately *precommit* and only demonstrates restoration
of changed in-memory candidate values; lower-level store tests cover real
Keychain error preservation.

`P1HTTPProbe.ownerADefinition` and `ownerBDefinition` are candidate-host examples
using the normal Definition, lifetime, store access, and management removal paths.
Their loopback fixture is `Tests/Fixtures/network_server.py`; it uses fixed values
and never reaches an external service.
