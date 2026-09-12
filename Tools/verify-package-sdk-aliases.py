#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("--swift", default="swift")
parser.add_argument("--evidence-dir", type=Path, required=True)
args = parser.parse_args()

repo = Path(__file__).resolve().parents[1]
fixtures = repo / "Tests" / "PackageSDKAliases"
evidence = args.evidence_dir.resolve()
evidence.mkdir(parents=True, exist_ok=True)


def run(name, command, cwd):
    result = subprocess.run(
        [str(part) for part in command],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    (evidence / f"{name}.log").write_text(result.stdout, encoding="utf-8")
    return result


def require_success(name, result):
    if result.returncode != 0:
        raise RuntimeError(f"{name} failed; see {evidence / f'{name}.log'}")


version = run("swift-version", [args.swift, "--version"], repo)
require_success("swift-version", version)

summary = {"swiftVersion": version.stdout.strip(), "cases": {}}
for case in ("StandaloneA", "StandaloneB", "CombinedAliased"):
    package = fixtures / case
    scratch = evidence / "scratch" / case
    resolved = run(
        f"{case}-resolve",
        [args.swift, "package", "--package-path", package, "--scratch-path", scratch, "resolve"],
        repo,
    )
    require_success(f"{case}-resolve", resolved)
    tested = run(
        f"{case}-test",
        [args.swift, "test", "--package-path", package, "--scratch-path", scratch],
        repo,
    )
    require_success(f"{case}-test", tested)
    summary["cases"][case] = {"resolve": "passed", "test": "passed"}

unaliased = fixtures / "CombinedUnaliased"
unaliased_scratch = evidence / "scratch" / "CombinedUnaliased"
unaliased_resolve = run(
    "CombinedUnaliased-resolve",
    [
        args.swift,
        "package",
        "--package-path",
        unaliased,
        "--scratch-path",
        unaliased_scratch,
        "resolve",
    ],
    repo,
)
if unaliased_resolve.returncode == 0:
    collision_result = run(
        "CombinedUnaliased-test",
        [
            args.swift,
            "test",
            "--package-path",
            unaliased,
            "--scratch-path",
            unaliased_scratch,
        ],
        repo,
    )
    collision_stage = "test"
else:
    collision_result = unaliased_resolve
    collision_stage = "resolve"

if collision_result.returncode == 0:
    raise RuntimeError("CombinedUnaliased unexpectedly succeeded without module aliases")

collision_log = collision_result.stdout
collision_pattern = re.compile(
    r"multiple packages.*conflicting name.*VendorSDK|"
    r"multiple similar targets.*VendorSDK|"
    r"VendorSDK.*(?:conflict|collision)",
    re.IGNORECASE | re.DOTALL,
)
package_identities = ("vendora", "vendorb")
if not collision_pattern.search(collision_log) or not all(
    identity in collision_log.lower() for identity in package_identities
):
    raise RuntimeError(
        "CombinedUnaliased failed without the expected VendorSDK collision diagnostic"
    )

summary["cases"]["CombinedUnaliased"] = {
    "resolve": "passed" if unaliased_resolve.returncode == 0 else "expected collision",
    "test": "expected collision" if collision_stage == "test" else "not run",
    "collisionStage": collision_stage,
    "requiredDiagnosticTerms": ["VendorSDK", *package_identities],
}
(evidence / "summary.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
print("Standalone A/B passed; unaliased VendorSDK collision was diagnosed; aliased graph passed")
