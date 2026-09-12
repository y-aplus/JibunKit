# Package-owned static Widget comparison

This bounded D26 fixture gives two independent Swift packages ownership of their own
`Widget`, `TimelineProvider`, entry view, stable `kind`, and owner-prefixed storage key.
It compares standalone A, standalone B, and one combined Widget extension whose standard
`WidgetBundle` includes both package types.

Both packages use the same local key, `shared-value`, and the existing
`MiniAppContext.storageKey(_:)` contract to address values stored in a shared
`UserDefaults` suite. The Timeline comparison writes different A/B values, updates A,
and requires B's provider output to remain unchanged.

The native build must show that each standalone host embeds one extension and the
combined host embeds one extension—not one extension per Feature. Binary kind ownership
is only link evidence; provider timeline output is compared separately. Neither is
treated as WidgetKit registration or gallery visibility.

The fixture does not change Counter, the production registry, code generation, or the
App Intents contract. Simulator widget-gallery presence is recorded only if directly
observed; otherwise it remains unverified.

## CI evidence

Run [34563868864](https://github.com/y-aplus/JibunKit/actions/runs/34563868864), source
`9429c659d7511e785f25faa7a77041f9d6ea38fd`, passed on Xcode 26.6 and iPhone 17
Simulator (iOS 26.5).

Native Release builds produced the following host/extension parent-child pairs:

- `StandaloneA.app` with exactly one `StandaloneAWidget.appex`, containing only
  `com.jibunkit.fixture.feature-a.widget`.
- `StandaloneB.app` with exactly one `StandaloneBWidget.appex`, containing only
  `com.jibunkit.fixture.feature-b.widget`.
- `Combined.app` with exactly one `CombinedWidget.appex`, containing both stable kinds.

All three embedded bundles declared the standard
`com.apple.widgetkit-extension` extension point. The combined result is the union of
the standalone kinds without adding a second extension. Therefore static package-owned
Widgets do not require one extension per Feature or a custom generator; a standard
host-owned `WidgetBundle` can compose both package types into one extension.

Focused `TimelineTests/testPackageTimelinesRemainOwnerScoped` passed in 0.003 seconds.
The original run verified distinct kinds and owner-prefixed `owner-a.shared-value` /
`owner-b.shared-value` timeline entries. A follow-up run below replaces those constant
entry checks with real shared-suite writes and provider reads. The normal search regression
`MigrationUITests/testMiniAppSearchFiltersAndOpensResults` also passed in 35.367 seconds.

The `Package-Widget-diagnostics` artifact is ID `10185620484`, SHA-256
`b2687d68741d0aedabaa474c7e1f5f0e179476ec6697eced0c8f594cda83c6d2`.

The run did not open or inspect the Simulator widget gallery. Gallery discoverability
is unverified and is not inferred from successful extension compilation or metadata.

## Stored-value isolation follow-up

Run [34566580764](https://github.com/y-aplus/JibunKit/actions/runs/34566580764), source
`97cc705475d2697737cc85abb54b2706fa6650b8`, passed after strengthening the fixture.
Both packages now use `MiniAppContext.storageKey(_:)` with the identical local key
`shared-value` against one real `UserDefaults` suite. The test wrote A=11 and B=22,
read those values through each package's Timeline provider, updated A to 33, and verified
B remained 22. `testPackageTimelinesRemainOwnerScoped` passed in 0.025 seconds.

The same run verified these required bundle-ID relationships:

- `com.jibunkit.fixture.standalone-a.Widget` is embedded by
  `com.jibunkit.fixture.standalone-a`.
- `com.jibunkit.fixture.standalone-b.Widget` is embedded by
  `com.jibunkit.fixture.standalone-b`.
- `com.jibunkit.fixture.combined.Widget` is embedded by
  `com.jibunkit.fixture.combined`.

Every xcodebuild invocation now captures stdout to the diagnostic artifact before
raising on a nonzero exit. The normal search regression passed in 60.418 seconds.
`Package-Widget-diagnostics` artifact ID `10186680931` has SHA-256
`75243901567c1dd86cb676ba97558a039b86c44de6c48507addd339ae0ba9a35`.

No gallery UI was directly observed in this headless CI run. Binary strings establish
that the stable kind constants were linked into each extension; they do not establish
WidgetKit registration, gallery discovery, rendering, or installation.

## Widget gallery and rendered-value follow-up

Run [34578792277](https://github.com/y-aplus/JibunKit/actions/runs/34578792277), source
`fb34f65790b1f48a3b0c043f6183776329fabcf9`, passed on Xcode 26.6 and iPhone 17
Simulator. Unlike the earlier build-only evidence, this run opened SpringBoard's public
Widget gallery and tested all three fixture hosts.

The standalone A and B cases each found the expected app and Feature configuration in
the gallery. Vision text recognition, restricted to the observed Widget preview frame,
read `A:11` and `B:22` respectively. The test selected the observed `Add Widget` Button,
returned to the home screen, and recognized the same value from a separate screenshot.
Both gallery UI tests passed with zero failures.

The combined case found both Feature A and Feature B under `Widget Fixture Combined`.
Its two preview screenshots recognized `A:11` and `B:22`. After adding both Widgets, one
home-screen screenshot contained `A:11` and `B:22`. The host then updated only A, and a
later single home-screen screenshot contained `A:33` and `B:22`; the strict observation
set did not contain `A:11`. This directly verifies that the displayed B value remained
unchanged while the displayed A value refreshed.

The exported screenshots were visually inspected in addition to the exact OCR checks:
the standalone home screens visibly show their one expected Widget, and the combined
home screens visibly show both Widgets before and after the A update. OCR mismatch is a
test failure rather than a skip, and each retained screenshot has a paired attachment
containing the raw recognized strings.

The same run also reconfirmed the surrounding evidence:

- Native Release builds preserved the standalone A/B kinds and their union in one
  combined extension.
- `TimelineTests/testPackageTimelinesRemainOwnerScoped` passed in 0.020 seconds.
- `StandaloneAGalleryUITests`, `StandaloneBGalleryUITests`, and
  `CombinedGalleryUITests` each executed one test with zero failures.
- The normal-search regression
  `MigrationUITests/testMiniAppSearchFiltersAndOpensResults` passed in 40.380 seconds.

The `Package-Widget-diagnostics` artifact is ID `10191568434`, 35,107,165 bytes, with
SHA-256 `6137fc298eb7f702b4ff10e1d499e34e7d78325227af333f9ac8604083b47126`.
