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
