#!/usr/bin/env python3
"""Diagnose an explicit local Package/product connection using native manifest dumps.

This checks declarations, not compilation, runtime Registry membership, or an IPA.
Tuist 4.207.0 ProjectDescription Codable is the supported project dump format.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys


class ConnectionError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ConnectionError(message)


def local_path(value, project_root):
    require(isinstance(value, dict) and isinstance(value.get("pathString"), str),
            "Unsupported Tuist path data; regenerate the dump with pinned Tuist.")
    kind = value.get("type")
    if kind == "relativeToManifest":
        base = project_root
    elif kind == "relativeToCurrentFile":
        require(isinstance(value.get("callerPath"), str), "Tuist path has no callerPath.")
        base = Path(value["callerPath"]).parent
    elif kind == "relativeToRoot":
        base = project_root
        while not ((base / "Tuist").is_dir() or (base / ".git").exists()):
            require(base.parent != base, "Cannot resolve Tuist root-relative package path.")
            base = base.parent
    else:
        raise ConnectionError(f"Unsupported Tuist path type: {kind}")
    return (base / value["pathString"]).resolve()


def inspect(project, package, project_root, package_root, product_name, host_name):
    require(isinstance(project, dict) and isinstance(project.get("packages"), list)
            and isinstance(project.get("targets"), list),
            "Unsupported project dump; use tuist dump on Project.swift.")
    require(isinstance(package, dict) and isinstance(package.get("products"), list)
            and isinstance(package.get("targets"), list),
            "Unsupported package dump; use swift package dump-package.")
    paths = []
    for entry in project["packages"]:
        require(isinstance(entry, dict), "Unsupported Tuist package declaration.")
        if "local" in entry:
            paths.append(local_path(entry["local"].get("path"), project_root))
        else:
            require("remote" in entry or "registry" in entry, "Unsupported Tuist package kind.")
    require(package_root.resolve() in paths,
            f"Package path missing: add {package_root} to {project_root / 'Project.swift'} packages.")
    products = [p for p in package["products"] if p.get("name") == product_name]
    require(len(products) == 1,
            f"Library product {product_name!r} missing or duplicated: check {package_root / 'Package.swift'} products.")
    product = products[0]
    require(isinstance(product.get("type"), dict) and "library" in product["type"],
            f"{product_name} is not a library product. Keep the standalone app/executable separate.")
    targets = {t["name"]: t for t in package["targets"]}
    require(product.get("targets"), f"{product_name} has no library targets in Package.swift.")
    for name in product["targets"]:
        require(name in targets, f"Product {product_name} references missing target {name}: fix Package.swift targets.")
        require(targets[name].get("type") not in {"executable", "test", "plugin"},
                f"Product {product_name} includes non-library target {name}: separate the app/test/plugin target.")
    hosts = [t for t in project["targets"] if t.get("name") == host_name]
    require(len(hosts) == 1, f"Host target {host_name!r} missing or duplicated: check Project.swift targets.")
    dependencies = hosts[0].get("dependencies")
    require(isinstance(dependencies, list), "Unsupported host dependency data in Tuist dump.")
    require(any(isinstance(d, dict) and d.get("package", {}).get("product") == product_name
                for d in dependencies),
            f"Host dependency missing: add .package(product: \"{product_name}\") to {host_name} dependencies in Project.swift.")
    return (f"Declared connection passed: {package_root.name}/{product_name} -> {host_name}. "
            "Next: tuist generate, native build, then verify the expected Feature ID in the running Registry. "
            "This result does not prove compilation or Registry registration.")


def native_json(command, cwd):
    try:
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, encoding="utf-8")
    except FileNotFoundError as error:
        raise ConnectionError(f"Required tool unavailable: {command[0]}. Use macOS with the pinned build tools.") from error
    require(result.returncode == 0,
            f"Native manifest evaluation failed ({' '.join(command)}):\n{result.stderr[-6000:]}\n"
            "Fix this native error before checking the host connection.")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ConnectionError(f"{command[0]} did not return a JSON manifest; check pinned tool/version and output.") from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path("."))
    parser.add_argument("--package", type=Path, required=True, help="Path relative to --project, or absolute")
    parser.add_argument("--product", required=True)
    parser.add_argument("--host", default="JibunKit-App")
    args = parser.parse_args()
    root = args.project.resolve()
    package_root = (root / args.package).resolve()
    try:
        require((root / "Project.swift").is_file(), f"Missing project manifest: {root / 'Project.swift'}")
        require((package_root / "Package.swift").is_file(),
                f"Package path does not contain Package.swift: {package_root}. Check the checkout and --package.")
        package = native_json(["swift", "package", "--package-path", str(package_root), "dump-package"], root)
        project = native_json(["tuist", "dump", "--path", str(root)], root)
        print(inspect(project, package, root, package_root, args.product, args.host))
    except (ConnectionError, KeyError, TypeError) as error:
        print(f"Feature connection check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
