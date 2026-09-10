# D10 real-page Web storage ownership verification

Date: 2026-09-11

## Scope

The signed-iOS fixture supplies an HTML page with `loadHTMLString`, using the same
fixed `https://jibunkit.example/ownership` base URL in two Features. It does not
test an HTTP fetch or TLS. Both pages write
the same `localStorage` key, persistent cookie name, and IndexedDB
database/object-store/key through page JavaScript. The `WKWebViewConfiguration` receives each Feature's
`context.websiteDataStore()` before navigation.

The test observes navigation completion and verifies the page-installed
JavaScript API before enabling operations. The IndexedDB write resolves only
from the read-write transaction's `oncomplete`, after which every write returns
all three values read back by the page. Neither page loading nor write
completion is represented by an unconditional sleep.

## Native checks

`MiniAppWebDataTests.testFactoryReturnsPersistentNativeStoreForOwnerIdentifier`
checks that the wrapper returns a persistent native `WKWebsiteDataStore` with
the stable owner/profile identifier. The signed UI flow checks:

- owner A and B write different values using the same origin, storage names,
  and cookie;
- each page immediately reads back its own `localStorage`, cookie, and IndexedDB
  values;
- the app enters the normal background state before termination;
- both values survive process recreation;
- clearing A's native store completes before proceeding;
- the page observes A's database deletion without opening and recreating it;
- B remains readable after A is cleared and the app is recreated again.

The fixture uses only the dedicated `web-storage-owner-a` and
`web-storage-owner-b` stores. It never clears the default store or another
Feature's data. A failure remains an assertion failure; the test has no skip or
fixed-delay fallback for Cookie instability.

IndexedDB deletion waits for `IDBOpenDBRequest.onsuccess`. The absence check
uses `indexedDB.databases()` and does not call `indexedDB.open()` for a missing
database, avoiding a false “missing” result that recreates the database under
test. HTTP fetch and Service Worker storage remain out of scope.

## CI-only integration

The normal product target does not include either probe file. Feature-validation
CI copies `WebStorageOwnershipProbe.swift` and
`WebStorageOwnershipUITests.swift` into the temporary generated host and adds:

```swift
WebStorageOwnershipProbe.ownerADefinition,
WebStorageOwnershipProbe.ownerBDefinition,
```

Run only the dedicated test with the full selector:

`MigrationUITests/WebStorageOwnershipUITests/testPageStorageSurvivesBackgroundRestartAndOwnerClearPreservesOther`

The UI test prints every observed page result with the
`WEB-STORAGE-OWNERSHIP` prefix. A successful run is evidence for this HTML page,
origin, OS, and background/relaunch sequence; it does not guarantee immediate
durability after abrupt termination, every cookie attribute, or coordinated
deletion while other WebViews are active.

## localStorage and Cookie result

[GitHub Actions run 34505014278](https://github.com/y-aplus/JibunKit/actions/runs/34505014278)
on Xcode 26.6 succeeded. Source `ae6ba26` ran the exact three-part selector and
executed one ownership UI test in 91.121 seconds with zero failures. The log
recorded immediate page readback for A and B, A and B readback after the normal
background/termination/relaunch boundary, A removal followed by
`local=missing cookie=missing`, and B readback after A's removal and a second
relaunch. Every retained-value read contained both the expected `localStorage`
value and Cookie value.

The native-store unit test passed in 0.015 seconds. The complete shared suite
executed 135 tests with zero failures. The short normal-host search/open UI
regression also passed (one test, 43.680 seconds), as did the release iOS build,
IPA packaging, independent packages, generated Feature checks, and Records UI
tests. No sleep or skip was added to the ownership path.
