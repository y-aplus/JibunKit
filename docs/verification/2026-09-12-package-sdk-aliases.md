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
  requires both version strings and initial configuration values simultaneously, writes
  an explicit B value, then updates A and requires that written B value to remain
  unchanged before and after the A update.

All manifests use Swift tools version 6.0. The original comparison roots retain macOS 12;
the reusable Vendor and Feature packages additionally declare iOS 26.
`Tools/verify-package-sdk-aliases.py` runs `swift package resolve` and `swift test` for
the successful roots with separate scratch directories. Exit status zero is not enough:
each successful root must print the `Test Case ... passed` marker for its exact expected
XCTest method. For the unaliased root, the verifier records whichever native SwiftPM
stage first diagnoses the collision and validates the diagnostic before treating that
failure as expected.

Except when the Swift executable itself is unavailable, one case failure does not stop
the other independent comparisons. Each case and stage is printed as it completes, all
stdout/stderr logs are retained, and `summary.json` is written before the verifier exits
nonzero for any accumulated failures.

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
working-tree diff were checked locally; this machine has no Swift toolchain, so native
execution was delegated to CI.

The existing workflow has an opt-in `package_sdk_aliases_only` mode for this
comparison. It selects Xcode 26.6's Swift toolchain and runs only the four pure-Swift
configurations; the normal iOS/IPA job is skipped. Logs and summary are uploaded
without compiled scratch directories. This mode does not establish iOS integration.

Run [34684588973](https://github.com/y-aplus/JibunKit/actions/runs/34684588973), source
`0f2417cad13e0ee942b42b6f5026c1259133fcf0`, passed in the dedicated
`Native Swift SDK module aliases` job. The normal Xcode/iOS job was skipped. The host
reported Apple Swift 6.3.3 targeting `arm64-apple-macosx26.0`.

All four roots resolved successfully. The three positive roots then reported their exact
expected XCTest methods as passed:

- `StandaloneATests.StandaloneATests testUsesVendorA` passed in 0.002 seconds.
- `StandaloneBTests.StandaloneBTests testUsesVendorB` passed in 0.003 seconds.
- `CombinedAliasedTests.CombinedAliasedTests
  testBothSDKConfigurationsRemainIndependent` passed in 0.001 seconds.

The combined build log shows the unchanged `VendorSDK.swift` source compiled once as
module `VendorASDK` and once as module `VendorBSDK`. The combined XCTest therefore
executed both version/configuration paths, wrote B, updated A, and verified that B's
written value remained unchanged.

`CombinedUnaliased` resolution succeeded, but `swift test` stopped with SwiftPM's native
diagnostic: multiple similar targets named `VendorSDK` appeared in packages `vendorb`
and `vendora`, with `moduleAliases` recommended for distinct packages. This specific
diagnostic, rather than an arbitrary nonzero result, satisfied the expected-collision
case. The final summary contained no verification failures.

The `Package-SDK-alias-diagnostics` artifact is ID `10295028814`, 3,882 bytes, with
SHA-256 `f49b2472559edfabd6e57828aca1603738328b84022622f4ce040b6ff5b64ef4`.

## iOS bridge comparison design

The follow-up iOS fixture leaves both Vendor SDK and Feature source modules unchanged.
`LibraryBridge` is a standard Swift package with one library product,
`SDKAliasBridge`. Its Feature A and Feature B product dependencies apply the same
`VendorSDK` to `VendorASDK` / `VendorBSDK` aliases used by the successful macOS
comparison. The bridge exposes a value snapshot plus `@MainActor` A/B configuration
writes; it does not expose either colliding SDK module to the app target.

`IOSHost` is a thin Tuist-generated iOS 26 SwiftUI app. Its only package dependency is
the bridge's ordinary library product. The UI displays both SDK versions and both live
configuration values. The focused UI test performs this sequence:

1. Require exact displayed versions `vendor-a-1.0` and `vendor-b-2.0`, plus both default
   configuration values.
2. Write `ios-b-written` through the visible B button and require A's default and B's
   written value on screen.
3. Write `ios-a-updated` through the visible A button and require that exact A value,
   the retained `ios-b-written` value, and both original versions on screen.

Each displayed value is selected by a stable accessibility identifier, then its visible
label is compared for exact equality. The test retains a final screenshot. The driver
copies the fixture to a temporary directory, runs standard `tuist generate` and one
focused `xcodebuild test`, and saves the generation log, complete build/test log,
`ios-summary.json`, and `.xcresult`. A zero exit alone is insufficient: the exact
`testAliasedSDKConfigurationsRemainIndependentInIOSHost` XCTest pass marker and
`** TEST SUCCEEDED **` must both be present.

The Simulator test uses the same manual ad-hoc signing settings as the existing native
package fixtures. `ios-summary.json` is initialized before generation; if Tuist fails,
it records that stage and exit code and explicitly leaves the Xcode test as not run.

The limited SDK-alias workflow selects the iOS host when `simulator_tests=true`, and
otherwise selects the four original macOS roots. The first iOS run also reran the macOS
roots successfully. Subsequent iOS-only manifest changes reuse that evidence and skip
those unchanged builds. Normal IPA and unrelated iOS regressions remain skipped.

Local checks ran on Windows. The first native CI result is recorded below; a failed
Xcode graph must not be reclassified as an expected success. Even when passing, this evidence is limited to this Tuist host and still does
not place either SDK in the normal JibunKit registry or establish the broader isolation
cases excluded above.

## First iOS result: product reference collision

[CI 34685650822](https://github.com/y-aplus/JibunKit/actions/runs/34685650822),
source `e8edd79586e0db969a244fe3684495d7d66450a9`, failed on Xcode 26.6 / iOS 26.5
Simulator before compiling or running the UI test. All four original macOS comparisons
passed their contracts again (A 0.002s, B 0.002s, combined 0.001s, exact unaliased target
collision). Tuist generation and package resolution succeeded (114.308s).

`xcodebuild test` exited 65 at `ComputePackagePrebuildTargetDependencyGraph` with:

```text
PIFLoader: GUID 'PRODUCTREF-PACKAGE-PRODUCT:VendorSDK--5F8B1E115CC902A7-dynamic' has already been registered
```

`ios-summary.json` records `tuistGenerate=passed`, `xcodebuildTest=failed`,
`testCasePassed=false`, `testSucceeded=false`. Complete generation/test logs and the
failed result bundle were retained. No UI launch, runtime configuration isolation or
iOS module compilation is proved by this run. The normal IPA job was skipped.

The historical [Swift Forums report](https://forums.swift.org/t/modulealiases-not-working-for-package-dependencies/67305)
contains the same class of product-reference collision after moving aliases to the
proper product-dependency edge. It is supporting context, not proof of the exact cause
inside the Xcode 26.6 implementation. Our actual run is the evidence for this toolchain.

The next comparison changes only the iOS dependency manifests: Vendor A/B publish
unique `VendorAProduct` / `VendorBProduct` library product names, and each Feature's
product dependency follows that name. The SDK target/module remains `VendorSDK`;
Feature source imports, SDK types and bridge aliases remain unchanged. Four explicit
`Package.ios.swift.fixture` files replace only temporary iOS copies of `Package.swift`.
The original macOS manifests retain their same-product collision comparison.

This is a proposed manifest-edit workaround, not an assertion that module aliases alone
fix the original Xcode graph. It requires control of the dependency manifests (or a
maintained fork); runtime/source names and arbitrary third-party packages are not
silently rewritten. The next CI must still pass the exact iOS test and preserve B's
written value after updating A. Until then, this workaround is unverified.
