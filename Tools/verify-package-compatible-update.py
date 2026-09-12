#!/usr/bin/env python3
"""Run a fixed native Swift Package A-only compatible-update verification."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys


PACKAGE_MANIFEST = '''// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{name}",
    defaultLocalization: "en",
    platforms: [.macOS(.v12)],
    products: [.library(name: "{name}", targets: ["{name}"])],
    targets: [.target(name: "{name}", resources: [.process("Resources")])]
)
'''

RUNNER_MANIFEST = '''// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PackageCompatibleUpdateRunner",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(path: "../Packages/FeatureA"),
        .package(path: "../Packages/FeatureB"),
    ],
    targets: [
        .executableTarget(
            name: "CompatibleUpdateRunner",
            dependencies: [
                .product(name: "ResourceFeatureA", package: "FeatureA"),
                .product(name: "ResourceFeatureB", package: "FeatureB"),
            ]
        )
    ]
)
'''


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_digest(root: Path) -> str:
    value = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        value.update(path.relative_to(root).as_posix().encode("utf-8"))
        value.update(b"\0")
        value.update(path.read_bytes())
        value.update(b"\0")
    return value.hexdigest()


def write(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8", newline="\n")


def run_native(swift: str, runner: Path, log: Path, arguments: list[str]) -> None:
    command = [swift, "run", "--package-path", str(runner), "CompatibleUpdateRunner", *arguments]
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8")
    log.write_text(
        "command: " + " ".join(command) + "\n"
        + f"returncode: {result.returncode}\n"
        + "stdout:\n" + result.stdout
        + "stderr:\n" + result.stderr,
        encoding="utf-8",
        newline="\n",
    )
    if result.returncode != 0:
        raise RuntimeError(f"Native runner failed; inspect {log}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    swift = shutil.which("swift")
    if swift is None:
        raise RuntimeError("swift executable not found; run this verifier on the macOS native lane")

    repository = Path(__file__).resolve().parents[1]
    fixture = repository / "Tests" / "PackageCompatibleUpdate"
    resources = repository / "Tests" / "PackageResources"
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        raise RuntimeError(f"output must be absent or empty so prior evidence is not overwritten: {output}")
    output.mkdir(parents=True, exist_ok=True)

    packages = output / "Packages"
    feature_a = packages / "FeatureA"
    feature_b = packages / "FeatureB"
    shutil.copytree(resources / "FeatureA" / "Sources", feature_a / "Sources")
    shutil.copytree(resources / "FeatureB" / "Sources", feature_b / "Sources")
    write(feature_a / "Package.swift", PACKAGE_MANIFEST.format(name="ResourceFeatureA"))
    write(feature_b / "Package.swift", PACKAGE_MANIFEST.format(name="ResourceFeatureB"))
    shutil.copyfile(
        fixture / "FeatureAStoredValue.v1.swift",
        feature_a / "Sources" / "ResourceFeatureA" / "FeatureAStoredValue.swift",
    )
    shutil.copyfile(
        fixture / "FeatureBStoredValue.swift",
        feature_b / "Sources" / "ResourceFeatureB" / "FeatureBStoredValue.swift",
    )

    runner = output / "Runner"
    runner_source = runner / "Sources" / "CompatibleUpdateRunner" / "main.swift"
    write(runner / "Package.swift", RUNNER_MANIFEST)
    runner_source.parent.mkdir(parents=True)
    snapshots = output / "SourceSnapshots"
    snapshots.mkdir()
    logs = output / "logs"
    logs.mkdir()
    store = output / "store"
    store.mkdir()

    shutil.copyfile(fixture / "RunnerV1.swift", runner_source)
    shutil.copyfile(runner_source, snapshots / "RunnerV1.swift")
    shutil.copyfile(
        feature_a / "Sources" / "ResourceFeatureA" / "FeatureAStoredValue.swift",
        snapshots / "FeatureAStoredValue.v1.swift",
    )
    a_resources = feature_a / "Sources" / "ResourceFeatureA" / "Resources"
    b_resources = feature_b / "Sources" / "ResourceFeatureB" / "Resources"
    a_resources_before = tree_digest(a_resources)
    b_resources_before = tree_digest(b_resources)
    b_package_before = tree_digest(feature_b)
    run_native(swift, runner, logs / "v1.log", [str(store)])

    a_v1 = store / "feature-a.json"
    b_value = store / "feature-b.json"
    b_baseline = store / "feature-b.baseline.json"
    if not a_v1.is_file() or not b_value.is_file():
        raise RuntimeError("v1 runner did not create both Feature stores")
    shutil.copyfile(b_value, b_baseline)
    shutil.copyfile(a_v1, store / "feature-a.v1.json")
    a_v1_hash = digest(a_v1)
    b_v1_hash = digest(b_value)

    # The compatibility update changes only Feature A's package source. The
    # verifier runner is then rebuilt to exercise v2 APIs in a separate process.
    shutil.copyfile(
        fixture / "FeatureAStoredValue.v2.swift",
        feature_a / "Sources" / "ResourceFeatureA" / "FeatureAStoredValue.swift",
    )
    shutil.copyfile(
        feature_a / "Sources" / "ResourceFeatureA" / "FeatureAStoredValue.swift",
        snapshots / "FeatureAStoredValue.v2.swift",
    )
    shutil.copyfile(fixture / "RunnerV2.swift", runner_source)
    shutil.copyfile(runner_source, snapshots / "RunnerV2.swift")
    run_native(swift, runner, logs / "v2-update.log", ["update", str(store)])

    if digest(b_value) != b_v1_hash or b_value.read_bytes() != b_baseline.read_bytes():
        raise RuntimeError("Feature B persistence bytes changed during Feature A update")
    if tree_digest(feature_b) != b_package_before:
        raise RuntimeError("Feature B package changed during Feature A update")
    if tree_digest(a_resources) != a_resources_before or tree_digest(b_resources) != b_resources_before:
        raise RuntimeError("Package-owned resources changed during the source update")
    a_v2_valid = store / "feature-a.v2.valid.json"
    shutil.copyfile(a_v1, a_v2_valid)
    a_v2_hash = digest(a_v2_valid)

    corrupt = b'{"name":'
    a_v1.write_bytes(corrupt)
    corrupt_hash = digest(a_v1)
    run_native(swift, runner, logs / "v2-reject-corrupt.log", ["reject-corrupt", str(store)])
    if digest(a_v1) != corrupt_hash or a_v1.read_bytes() != corrupt:
        raise RuntimeError("Rejected Feature A corruption was modified or replaced")
    if digest(b_value) != b_v1_hash:
        raise RuntimeError("Feature B persistence changed during corrupt A rejection")

    result = {
        "result": "passed",
        "scope": "macOS Swift Package runner; no iOS/UIKit/IPA claim",
        "processes": ["v1", "v2-update", "v2-reject-corrupt"],
        "hashes": {
            "feature_a_v1": a_v1_hash,
            "feature_a_v2_valid": a_v2_hash,
            "feature_a_corrupt_preserved": corrupt_hash,
            "feature_b_preserved": b_v1_hash,
            "feature_b_package_preserved": b_package_before,
            "feature_a_resources_preserved": a_resources_before,
            "feature_b_resources_preserved": b_resources_before,
        },
        "logs": ["logs/v1.log", "logs/v2-update.log", "logs/v2-reject-corrupt.log"],
    }
    write(output / "result.json", json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"Package-compatible update verification passed; evidence: {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"package-compatible update verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
