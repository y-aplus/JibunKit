# Swift Package resource and localization comparison (2026-09-11)

## Question

When two Swift packages contain the same resource filename and localization key but different values, does standard `Bundle.module` preserve each package's values when built alone and together? After removing Feature A and regenerating into the same DerivedData, does Feature B still read its own values, independently of any stale A bundle left on disk?

## Fixture and boundaries

`Tests/PackageResources/FeatureA` and `FeatureB` are independent Swift packages. Each processes a resource named `shared.json` and `en.lproj` / `ja.lproj` `Localizable.strings` files containing the key `shared.greeting`. A's values identify A and B's identify B. Their public readers use only `Bundle.module`, `JSONSerialization`, and `Bundle.localizedString(forKey:value:table:)`. The UI test launches each configuration separately with English and Japanese app-language settings; it does not treat `String`'s formatting locale as a resource-language override.

The optional `package_resources_validation` CI hook generates a dedicated iOS app and UI test. With one app identity and one DerivedData directory it executes A-only, B-only, combined A+B, then B-only after regenerating the project without A. Every run reads actual JSON and explicit English/Japanese localized values in the simulator. After the combined build and after the removal build, the hook separately counts any A resource bundles still present in DerivedData; runtime correctness is not inferred from filesystem cleanup.

This comparison covers SwiftPM resource-bundle identity, the standard package accessor, explicit en/ja lookup, generated-project dependency removal, and this build cache sequence. It does not establish coexistence for arbitrary SDK globals or runtime singletons. No custom resource generator or cleanup step is introduced.

CI evidence pending.
