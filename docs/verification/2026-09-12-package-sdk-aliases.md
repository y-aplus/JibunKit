# SwiftPM module aliases for same-named pure-Swift SDK modules

This D29 fixture compares two independent local package identities, `vendora` and
`vendorb`. Each publishes a pure-Swift library product and target named `VendorSDK`.
Their source APIs deliberately have the same public type names, `SDKInfo` and
`SDKConfiguration`; only their version strings and initial shared-configuration values
differ.

`FeatureA` depends on Vendor A and `FeatureB` depends on Vendor B. Each Feature imports
the unchanged source name `VendorSDK` and exposes its SDK version and `@MainActor`
shared configuration through a small public client. The SDK sources do not contain
generated namespaces or conditional renaming.

## Comparison

The fixture contains four root packages:

- `StandaloneA` requires Vendor A's version and configuration, updates that
  configuration, and reads it back.
- `StandaloneB` performs the equivalent assertions for Vendor B.
- `CombinedUnaliased` connects both Feature products without aliases. Its resolve or
  test command must fail with SwiftPM's specific duplicate-`VendorSDK` diagnostic naming
  both `vendora` and `vendorb`; an arbitrary nonzero build result is rejected.
- `CombinedAliased` uses only PackageDescription's standard
  `.product(..., moduleAliases:)` API, mapping the transitive source module to
  `VendorASDK` on the Feature A edge and `VendorBSDK` on the Feature B edge. Its XCTest
  requires both version strings and initial configuration values simultaneously, then
  updates A and requires B to remain unchanged.

`Tools/verify-package-sdk-aliases.py` runs `swift package resolve` and `swift test` for
the successful roots with separate scratch directories. For the unaliased root, it
records whichever native SwiftPM stage first diagnoses the collision and validates the
diagnostic before treating that failure as expected. All stdout/stderr, the Swift
version, and a JSON summary are retained in the requested evidence directory.

Expected invocation:

```sh
python3 Tools/verify-package-sdk-aliases.py \
  --evidence-dir "$RUNNER_TEMP/PackageSDKAliases"
```

The fixture is intentionally small: it launches one Swift version query, four resolve
operations, three successful tests, and at most one unaliased test after resolution.
The dominant cost is four clean SwiftPM scratch builds of tiny pure-Swift modules; no
Simulator, Xcode project generation, signing, network dependency, or app installation is
involved.

## Standard API and boundaries

[SE-0339](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0339-module-aliasing-for-disambiguation.md)
defines module aliasing at the product dependency where a conflict occurs. The SwiftPM
[changelog](https://github.com/swiftlang/swift-package-manager/blob/main/CHANGELOG.md)
records the manifest feature in Swift 5.7, and Swift.org's
[Swift 5.7 release notes](https://www.swift.org/blog/swift-5.7-released/) list SE-0339 as
implemented. The accepted proposal explicitly excludes precompiled modules that cannot
be rebuilt under the alias.

Therefore a passing comparison would establish only that same-named, source-built
pure-Swift modules from different package identities can coexist when the consumer
supplies unique aliases. It would not establish that SwiftPM can resolve two versions of
one package identity. It also would not establish isolation for C or Objective-C symbols,
binary modules, process-wide OS singletons, keychain access groups, URL sessions, or any
other external state an SDK may use.

No JibunKit runtime or generator mechanism is proposed: if the native alias comparison
passes, the integration condition is to keep the SDKs under distinct package identities
and declare unique aliases at the consuming product edges.

## Verification status

The fixture and verifier were reviewed statically on Windows. Python syntax and the
working-tree diff are checked locally, but this machine has no Swift toolchain, so no
SwiftPM resolve, build, or XCTest result is claimed here. Native execution evidence must
be added only after the verifier runs on a Swift-equipped host.
