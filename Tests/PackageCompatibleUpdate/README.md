# Package-compatible update fixture

`Tools/verify-package-compatible-update.py --output PATH` copies the existing
PackageResources Feature A/B sources into `PATH`, adds these fixed persistence
models, and builds a small native Swift runner. It first runs v1 in a separate
process, updates only Feature A's package model to v2, and runs v2 against the
same storage directory. A final process verifies that corrupt A bytes are
rejected and remain byte-for-byte unchanged.

The generated directory retains package sources, runner sources, persisted
bytes, subprocess logs, hashes, and `result.json` for review. This fixture tests
Swift Package persistence/resource compatibility on macOS; it does not claim
iOS UI, UIKit, signing, or IPA success.

## Generated iOS host update

`Tools/prepare-package-compatible-update-host.py` operates on an explicit,
separate generated JibunKit host whose Project already depends on
ResourceFeatureA/B and whose Registry includes
`P0CCompatibleUpdateProbe.definition`. Set `$REPOSITORY` to the absolute source checkout and `$HOST` to the separate generated host (Project paths are `Tests/PackageResources/FeatureA` and `Tests/PackageResources/FeatureB`). Keep the source tool path absolute when changing directories. Prepare and test v1 first:

```sh
python "$REPOSITORY/Tools/prepare-package-compatible-update-host.py" --host "$HOST" --stage v1
cd "$HOST" && tuist generate --no-open
xcodebuild test -workspace JibunKit.xcworkspace -scheme MigrationUITests \
  -destination "id=$SIMULATOR_UDID" -derivedDataPath "$DERIVED_DATA" \
  -only-testing:MigrationUITests/P0CCompatibleUpdateV1UITests/testSeedV1ThroughNormalFeatureURL
```

Then update the same host and run the v2 selector on the same Simulator and
bundle ID. Do not erase the Simulator, uninstall the app, delete its container,
or run the v1 selector again:

```sh
python "$REPOSITORY/Tools/prepare-package-compatible-update-host.py" --host "$HOST" --stage v2
cd "$HOST" && tuist generate --no-open
xcodebuild test -workspace JibunKit.xcworkspace -scheme MigrationUITests \
  -destination "id=$SIMULATOR_UDID" -derivedDataPath "$DERIVED_DATA" \
  -only-testing:MigrationUITests/P0CCompatibleUpdateV2UITests/testReadUpdateRelaunchRejectCorruptionAndRepairWithoutReseeding
```

The second `xcodebuild test` rebuilds and installs the changed app over the
existing installation. The v2 test fails unless v1 container bytes are present;
it never seeds them. It then terminates/relaunches for the added-field read,
leaves rejected corrupt A bytes untouched, repairs A explicitly, and verifies B
bytes plus both packages' same-named JSON/translations at every stage.

The parent workflow selects the V1 class together with onboarding; its following
step runs the exact V2 method automatically. It records container A/B files before
and after update, the source invariant hashes, native logs and both xcresults.
The v1 API refuses existing owner files; the corrupt stage decodes the file it
actually wrote, and repair verifies those corrupt bytes survived relaunch.
Python tests and workflow preparation run on Windows; Swift/iOS execution is
still pending the consolidated CI.
