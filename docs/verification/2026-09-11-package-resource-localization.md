# Swift Package resource and localization comparison (2026-09-11)

## Question

When two Swift packages contain the same resource filename and localization key but different values, does standard `Bundle.module` preserve each package's values when built alone and together? After removing Feature A and regenerating into the same DerivedData, does Feature B still read its own values, independently of any stale A bundle left on disk?

## Fixture and boundaries

`Tests/PackageResources/FeatureA` and `FeatureB` are independent Swift packages. Each processes a resource named `shared.json` and `en.lproj` / `ja.lproj` `Localizable.strings` files containing the key `shared.greeting`. A's values identify A and B's identify B. Their public readers use only `Bundle.module`, `JSONSerialization`, and standard `Bundle` lookup. The dedicated host declares `CFBundleLocalizations = [en, ja]`, English as its development region, and `CFBundleAllowMixedLocalizations = true`; Apple defines the latter as allowing localized-string retrieval from framework bundles. Each configuration is launched separately with English and Japanese app-language settings and verifies ordinary `Bundle.module.localizedString`. Explicit en/ja sub-bundle reads are retained as a separate resource-presence comparison, not as evidence of normal language selection.

The optional `package_resources_validation` CI hook generates a dedicated iOS app and UI test. With one app identity and one DerivedData directory it executes A-only, B-only, combined A+B, then B-only after regenerating the project without A. Every run reads actual JSON and explicit English/Japanese localized values in the simulator. After the combined build and after the removal build, the hook separately counts any A resource bundles still present in DerivedData; runtime correctness is not inferred from filesystem cleanup.

This comparison covers SwiftPM resource-bundle identity, the standard package accessor, explicit en/ja lookup, generated-project dependency removal, and this build cache sequence. It does not establish coexistence for arbitrary SDK globals or runtime singletons. No custom resource generator or cleanup step is introduced.

Run [34569632534](https://github.com/y-aplus/JibunKit/actions/runs/34569632534) established the explicit resource-presence baseline. A-only returned `A|Hello from A|Aからこんにちは`; B-only returned the corresponding B values; combined returned both complete A then B value sets; and B after A removal still returned only B's values. Two A resource-bundle directories existed in DerivedData before removal and one remained afterward, while the regenerated/rerun app still read B correctly. Thus stale on-disk A output and runtime B lookup are distinct. This run predates the host localization declaration and does not establish ordinary preferred-language selection.

Run [34570995724](https://github.com/y-aplus/JibunKit/actions/runs/34570995724) is the successful source for the corrected host-language comparison at commit `009f713`. Each result is ordered as JSON owner, ordinary preferred-language lookup, explicit English lookup, and explicit Japanese lookup:

- A-only (19.288 seconds): English returned `A|Hello from A|Hello from A|Aからこんにちは`; Japanese returned `A|Aからこんにちは|Hello from A|Aからこんにちは`.
- B-only (18.727 seconds): English returned `B|Hello from B|Hello from B|Bからこんにちは`; Japanese returned `B|Bからこんにちは|Hello from B|Bからこんにちは`.
- Combined A+B (22.396 seconds): English returned `A|Hello from A|Hello from A|Aからこんにちは|B|Hello from B|Hello from B|Bからこんにちは`; Japanese returned `A|Aからこんにちは|Hello from A|Aからこんにちは|B|Bからこんにちは|Hello from B|Bからこんにちは`.
- B-only after removing A and regenerating into the same DerivedData (14.092 seconds): English and Japanese repeated the exact B-only values above.

There were two A resource-bundle directories in DerivedData after the combined build and one after the regenerated B-only build. The remaining stale A directory is an on-disk cache observation; it did not cause B to load A's JSON or localized string at runtime. The existing mini-app Search regression also passed in 37.953 seconds.

The host localization declaration is part of the verified standard connection, not optional test decoration: without it, earlier runs fell back to English during a Japanese launch. The current app-side fixture chooses its expected ordinary value from `Locale.preferredLanguages`; by itself that assertion could pass with English if an `-AppleLanguages` request were ignored and the reported preference also stayed English. This run's separate `language=ja` log contains the actual Japanese ordinary values for both packages, so the result is supported for this run. A future code change should additionally have the UI test assert that the app's observed selected language equals its requested en/ja value; that assertion improvement does not justify rerunning this already conclusive comparison by itself.

## Apple references

- [`CFBundleLocalizations`](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundlelocalizations)
- [`CFBundleAllowMixedLocalizations`](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleallowmixedlocalizations)
- [`Bundle`](https://developer.apple.com/documentation/foundation/bundle)
