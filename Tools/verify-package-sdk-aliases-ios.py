#!/usr/bin/env python3
import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("--simulator-id", required=True)
parser.add_argument("--tuist", default="tuist")
parser.add_argument("--evidence-dir", type=Path, required=True)
args = parser.parse_args()

repo = Path(__file__).resolve().parents[1]
fixtures = repo / "Tests" / "PackageSDKAliases"
evidence = args.evidence_dir.resolve()
evidence.mkdir(parents=True, exist_ok=True)
method = "testAliasedSDKConfigurationsRemainIndependentInIOSHost"
summary = {
    "method": method,
    "tuistGenerate": {"exitCode": None, "status": "not run"},
    "xcodebuildTest": {"exitCode": None, "status": "not run"},
    "testCasePassed": False,
    "testSucceeded": False,
}


def write_summary():
    (evidence / "ios-summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def run(name, command, cwd):
    result = subprocess.run(
        [str(part) for part in command],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    (evidence / f"{name}.log").write_text(result.stdout, encoding="utf-8")
    print(result.stdout, end="")
    return result


with tempfile.TemporaryDirectory(prefix="jibunkit-sdk-alias-ios-") as temp:
    root = Path(temp)
    shutil.copytree(fixtures, root, dirs_exist_ok=True)
    host = root / "IOSHost"
    (host / "Project.swift").write_text(
        (host / "Project.swift.fixture").read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    (host / "Tuist").mkdir()

    generated = run(
        "tuist-generate",
        [args.tuist, "generate", "--no-open"],
        host,
    )
    summary["tuistGenerate"] = {
        "exitCode": generated.returncode,
        "status": "passed" if generated.returncode == 0 else "failed",
    }
    if generated.returncode != 0:
        write_summary()
        raise RuntimeError("Tuist generation failed; see tuist-generate.log")

    result_bundle = evidence / "SDKAliasIOS.xcresult"
    test_identifier = f"SDKAliasHostUITests/SDKAliasHostUITests/{method}"
    command = [
        "xcodebuild",
        "test",
        "-workspace",
        "SDKAliasIOS.xcworkspace",
        "-scheme",
        "SDKAliasHost",
        "-configuration",
        "Debug",
        "-destination",
        f"platform=iOS Simulator,id={args.simulator_id}",
        "-derivedDataPath",
        root / "DerivedData",
        "-resultBundlePath",
        result_bundle,
        "-parallel-testing-enabled",
        "NO",
        f"-only-testing:{test_identifier}",
        "CODE_SIGNING_ALLOWED=YES",
        "CODE_SIGN_IDENTITY=-",
        "CODE_SIGN_STYLE=Manual",
    ]
    tested = run("xcodebuild-test", command, host)
    marker = re.search(
        rf"Test Case '-\[SDKAliasHostUITests\.SDKAliasHostUITests "
        rf"{re.escape(method)}\]' passed",
        tested.stdout,
    )
    succeeded = "** TEST SUCCEEDED **" in tested.stdout
    summary["xcodebuildTest"] = {
        "exitCode": tested.returncode,
        "status": "passed" if tested.returncode == 0 else "failed",
    }
    summary["testCasePassed"] = marker is not None
    summary["testSucceeded"] = succeeded
    write_summary()
    if tested.returncode != 0 or marker is None or not succeeded:
        raise RuntimeError(
            "iOS SDK alias UI test did not report its exact method and TEST SUCCEEDED"
        )

print("iOS SDK alias bridge linked and preserved independent displayed configuration")
