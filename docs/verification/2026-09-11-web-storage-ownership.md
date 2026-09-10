# D10 real-page Web storage ownership verification

Date: 2026-09-11

## Scope

The signed-iOS fixture loads an HTML page at the same fixed
`https://jibunkit.example/ownership` origin in two Features. Both pages write
the same `localStorage` key and the same persistent cookie name through page
JavaScript. The `WKWebViewConfiguration` receives each Feature's
`context.websiteDataStore()` before navigation.

The test observes navigation completion and verifies the page-installed
JavaScript API before enabling operations. Every write returns the values read
back by the page, so neither page loading nor write completion is represented by
an unconditional sleep.

## Native checks

`MiniAppWebDataTests.testFactoryReturnsPersistentNativeStoreForOwnerIdentifier`
checks that the wrapper returns a persistent native `WKWebsiteDataStore` with
the stable owner/profile identifier. The signed UI flow checks:

- owner A and B write different values using the same origin, key, and cookie;
- each page immediately reads back its own `localStorage` and cookie values;
- the app enters the normal background state before termination;
- both values survive process recreation;
- clearing A's native store completes before proceeding;
- B remains readable after A is cleared and the app is recreated again.

The fixture uses only the dedicated `web-storage-owner-a` and
`web-storage-owner-b` stores. It never clears the default store or another
Feature's data. A failure remains an assertion failure; the test has no skip or
fixed-delay fallback for Cookie instability.

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
