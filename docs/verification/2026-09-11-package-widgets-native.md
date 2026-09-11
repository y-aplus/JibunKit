# Package-owned static Widget comparison

This bounded D26 fixture gives two independent Swift packages ownership of their own
`Widget`, `TimelineProvider`, entry view, stable `kind`, and owner-prefixed storage key.
It compares standalone A, standalone B, and one combined Widget extension whose standard
`WidgetBundle` includes both package types.

The native build must show that each standalone host embeds one extension and the
combined host embeds one extension—not one extension per Feature. Binary kind ownership
and provider timeline output are compared separately so successful compilation is not
mistaken for gallery visibility.

The fixture does not change Counter, the production registry, code generation, or the
App Intents contract. Simulator widget-gallery presence is recorded only if directly
observed; otherwise it remains unverified.

## CI evidence

Run [34563868864](https://github.com/y-aplus/JibunKit/actions/runs/34563868864), source
`9429c659d7511e785f25faa7a77041f9d6ea38fd`, passed on Xcode 26.6 and iPhone 17
Simulator (iOS 26.5).

Native Release builds produced:

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
It verified distinct kinds and owner-prefixed `owner-a.shared-value` /
`owner-b.shared-value` timeline entries. The normal search regression
`MigrationUITests/testMiniAppSearchFiltersAndOpensResults` also passed in 35.367 seconds.

The `Package-Widget-diagnostics` artifact is ID `10185620484`, SHA-256
`b2687d68741d0aedabaa474c7e1f5f0e179476ec6697eced0c8f594cda83c6d2`.

The run did not open or inspect the Simulator widget gallery. Gallery discoverability
is unverified and is not inferred from successful extension compilation or metadata.
