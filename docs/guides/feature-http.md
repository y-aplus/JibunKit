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

The P1-B candidate adds `lifetime.withStoppedOperation` for external cleanup
such as logout. Call it outside runtime-owned work: it drains that work, runs
the cleanup, and makes concurrent start/stop and management wait for actual
completion. Inside the operation, obtain the normal exclusive
`withStoreMaintenance` reservation before changing stored credentials/cookies.
The boundary does not reopen management admission or automatically restart the
Feature. A normal resume request waits until the cleanup completes. Cancellation
also waits for actual completion; the operation determines whether cancellation
occurred before or after its durable commit. Do not call start/stop, restore
lifecycle, or another stopped operation on the same lifetime from the callback.
This candidate addition passed shared Swift tests in run34802338245 and the
normal-host HTTP/logout/management UI flow in the successful network job of
run34816553410. That run failed in its separate Web job; it is not an overall
green-run claim. It is not part of the published 0.7.0 contract. See the
[P1-B evidence](../verification/2026-09-14-p1-b.md) for method results and
remaining device checks.

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
For the device candidate their loopback fixture is
`Tests/TemplateIntegration/P1DeviceHTTPFixture.swift`, running inside the app at
127.0.0.1:8766. No PC server is needed. CI can also use the external
`Tests/Fixtures/network_server.py` through an explicit test-runner environment
override. Both use diagnostic credentials and avoid external services. These
servers are test fixtures, not a mandatory transport or authentication provider
for Features built with JibunKit.
