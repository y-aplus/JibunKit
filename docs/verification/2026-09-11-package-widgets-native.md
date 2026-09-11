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
