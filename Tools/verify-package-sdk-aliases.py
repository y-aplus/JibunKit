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


version = run("swift-version", [args.swift, "--version"], repo)
if version.returncode != 0:
    raise RuntimeError(f"swift-version failed; see {evidence / 'swift-version.log'}")

summary = {"swiftVersion": version.stdout.strip(), "cases": {}, "failures": []}
expected_tests = {
    "StandaloneA": "StandaloneATests.StandaloneATests testUsesVendorA",
    "StandaloneB": "StandaloneBTests.StandaloneBTests testUsesVendorB",
    "CombinedAliased": (
        "CombinedAliasedTests.CombinedAliasedTests "
        "testBothSDKConfigurationsRemainIndependent"
    ),
}


def report(case, stage, outcome):
    print(f"{case} {stage}: {outcome}")


for case, expected_test in expected_tests.items():
    package = fixtures / case
    scratch = evidence / "scratch" / case
    case_summary = {}
    summary["cases"][case] = case_summary
    resolved = run(
        f"{case}-resolve",
        [args.swift, "package", "--package-path", package, "--scratch-path", scratch, "resolve"],
        repo,
    )
    if resolved.returncode != 0:
        case_summary["resolve"] = "failed"
        case_summary["test"] = "not run"
        summary["failures"].append(f"{case} resolve failed")
        report(case, "resolve", "failed")
        continue
    case_summary["resolve"] = "passed"
    report(case, "resolve", "passed")
    tested = run(
        f"{case}-test",
        [args.swift, "test", "--package-path", package, "--scratch-path", scratch],
        repo,
    )
    passed_line = re.compile(
        rf"Test Case '-\[{re.escape(expected_test)}\]' passed"
    ).search(tested.stdout)
    if tested.returncode != 0 or passed_line is None:
        case_summary["test"] = "failed"
        case_summary["expectedTest"] = expected_test
        summary["failures"].append(
            f"{case} did not report its expected XCTest method as passed"
        )
        report(case, "test", "failed or expected method marker absent")
    else:
        case_summary["test"] = "passed"
        case_summary["expectedTest"] = expected_test
        report(case, "test", "passed")

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
    collision_valid = False
else:
    collision_log = collision_result.stdout
    collision_pattern = re.compile(
        r"multiple packages.*conflicting name.*VendorSDK|"
        r"multiple similar targets.*VendorSDK|"
        r"VendorSDK.*(?:conflict|collision)",
        re.IGNORECASE | re.DOTALL,
    )
    package_identities = ("vendora", "vendorb")
    collision_valid = collision_pattern.search(collision_log) is not None and all(
        identity in collision_log.lower() for identity in package_identities
    )

unaliased_summary = {
    "resolve": "passed" if unaliased_resolve.returncode == 0 else "expected collision",
    "test": "expected collision" if collision_stage == "test" else "not run",
    "collisionStage": collision_stage,
    "requiredDiagnosticTerms": ["VendorSDK", "vendora", "vendorb"],
}
summary["cases"]["CombinedUnaliased"] = unaliased_summary
if collision_valid:
    report("CombinedUnaliased", collision_stage, "expected VendorSDK collision")
else:
    unaliased_summary["collision"] = "missing or invalid diagnostic"
    summary["failures"].append(
        "CombinedUnaliased did not emit the expected VendorSDK/vendora/vendorb collision"
    )
    report("CombinedUnaliased", collision_stage, "failed or collision diagnostic invalid")

(evidence / "summary.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
if summary["failures"]:
    print("Verification failures:")
    for failure in summary["failures"]:
        print(f"- {failure}")
    raise SystemExit(1)
print("Standalone A/B passed; unaliased VendorSDK collision was diagnosed; aliased graph passed")
