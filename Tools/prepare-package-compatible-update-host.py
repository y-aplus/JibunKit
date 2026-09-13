#!/usr/bin/env python3
"""Prepare one explicit generated JibunKit host for iOS v1/v2 update tests."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys


STATE_NAME = ".p0c-compatible-update-v1.json"


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_hash(path: Path) -> str:
    digest = hashlib.sha256()
    for item in sorted(candidate for candidate in path.rglob("*") if candidate.is_file()):
        digest.update(item.relative_to(path).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(item.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def invariant_hashes(host: Path) -> dict[str, str]:
    paths = {
        "root_package": host / "Package.swift",
        "project": host / "Project.swift",
        "registry": host / "Sources/JibunKit/MiniAppRegistry.swift",
        "probe": host / "Sources/JibunKit/P0CCompatibleUpdateProbe.swift",
        "ui_tests": host / "UITests/P0CCompatibleUpdateUITests.swift",
        "feature_a_manifest": host / "Tests/PackageResources/FeatureA/Package.swift",
        "feature_a_resource_api": host / "Tests/PackageResources/FeatureA/Sources/ResourceFeatureA/ResourceValues.swift",
    }
    directories = {
        "host_app_sources": host / "Sources/JibunKit",
        "ui_test_sources": host / "UITests",
        "feature_a_resources": host / "Tests/PackageResources/FeatureA/Sources/ResourceFeatureA/Resources",
        "feature_b_package": host / "Tests/PackageResources/FeatureB",
    }
    missing = [str(path) for path in [*paths.values(), *directories.values()] if not path.exists()]
    if missing:
        raise RuntimeError("prepared host is missing invariant input: " + ", ".join(missing))
    result = {name: file_hash(path) for name, path in paths.items()}
    result.update({name: tree_hash(path) for name, path in directories.items()})
    return result


def validate_host(host: Path, repository: Path) -> None:
    if host == repository:
        raise RuntimeError("--host must name a separate generated host, not this source checkout")
    for relative in ("Package.swift", "Project.swift", "Sources/JibunKit/MiniAppRegistry.swift"):
        if not (host / relative).is_file():
            raise RuntimeError(f"--host is not a prepared JibunKit host; missing {relative}")
    project = (host / "Project.swift").read_text(encoding="utf-8")
    registry = (host / "Sources/JibunKit/MiniAppRegistry.swift").read_text(encoding="utf-8")
    for product in ("ResourceFeatureA", "ResourceFeatureB"):
        if product not in project:
            raise RuntimeError(f"generated host must declare its {product} package dependency before preparation")
    if "P0CCompatibleUpdateProbe.definition" not in registry:
        raise RuntimeError("generated host Registry must include P0CCompatibleUpdateProbe.definition")


def prepare_v1(host: Path, repository: Path) -> None:
    state_path = host / STATE_NAME
    if state_path.exists():
        raise RuntimeError(f"v1 was already prepared; do not overwrite update evidence: {state_path}")
    source_packages = repository / "Tests/PackageResources"
    target_packages = host / "Tests/PackageResources"
    for feature in ("FeatureA", "FeatureB"):
        destination = target_packages / feature
        if not destination.resolve().is_relative_to(host.resolve()):
            raise RuntimeError(f"package destination escapes the explicit generated host: {destination}")
        if destination.exists():
            shutil.rmtree(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source_packages / feature, destination)

    probe_target = host / "Sources/JibunKit/P0CCompatibleUpdateProbe.swift"
    tests_target = host / "UITests/P0CCompatibleUpdateUITests.swift"
    probe_target.parent.mkdir(parents=True, exist_ok=True)
    tests_target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(repository / "Tests/TemplateIntegration/P0CCompatibleUpdateProbe.swift", probe_target)
    shutil.copyfile(repository / "Tests/TemplateIntegration/P0CCompatibleUpdateUITests.swift", tests_target)

    fixture = repository / "Tests/PackageCompatibleUpdate"
    a_source = target_packages / "FeatureA/Sources/ResourceFeatureA/FeatureAStoredValue.swift"
    b_source = target_packages / "FeatureB/Sources/ResourceFeatureB/FeatureBStoredValue.swift"
    shutil.copyfile(fixture / "FeatureAStoredValue.v1.swift", a_source)
    shutil.copyfile(fixture / "FeatureBStoredValue.swift", b_source)
    state = {
        "version": 1,
        "host": str(host),
        "feature_a_v1": file_hash(a_source),
        "invariants": invariant_hashes(host),
    }
    state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"prepared compatible-update v1 host: {host}")


def prepare_v2(host: Path, repository: Path) -> None:
    state_path = host / STATE_NAME
    if not state_path.is_file():
        raise RuntimeError("v2 requires the same host to be prepared with --stage v1 first")
    state = json.loads(state_path.read_text(encoding="utf-8"))
    if state.get("version") != 1 or state.get("host") != str(host):
        raise RuntimeError("v1 preparation metadata does not belong to this host")
    current = invariant_hashes(host)
    if current != state.get("invariants"):
        changed = sorted(set(current) | set(state.get("invariants", {})))
        changed = [name for name in changed if current.get(name) != state.get("invariants", {}).get(name)]
        raise RuntimeError("v2 refused because non-A host inputs changed: " + ", ".join(changed))

    fixture = repository / "Tests/PackageCompatibleUpdate"
    a_source = host / "Tests/PackageResources/FeatureA/Sources/ResourceFeatureA/FeatureAStoredValue.swift"
    if file_hash(a_source) != state.get("feature_a_v1"):
        raise RuntimeError("v2 refused because Feature A is not the prepared v1 source")
    shutil.copyfile(fixture / "FeatureAStoredValue.v2.swift", a_source)
    print(f"prepared compatible-update v2 by changing only {a_source}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--stage", choices=("v1", "v2"), required=True)
    args = parser.parse_args()
    repository = Path(__file__).resolve().parents[1]
    host = args.host.resolve()
    validate_host(host, repository)
    if args.stage == "v1":
        prepare_v1(host, repository)
    else:
        prepare_v2(host, repository)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"compatible-update host preparation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
