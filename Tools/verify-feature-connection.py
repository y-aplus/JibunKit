#!/usr/bin/env python3
"""Exercise connection diagnostics against real Swift/Tuist manifests on macOS.

One CI step tests a corrected connection and each independently broken source;
no Xcode build or runtime registration success is claimed by this experiment.
"""
from pathlib import Path
import subprocess
import sys
import tempfile


PACKAGE = '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Notes", platforms: [.iOS("26.0")],
    products: [.library(name: "NotesFeature", targets: ["NotesFeature"])],
    targets: [.target(name: "NotesFeature")])
'''
PROJECT = '''import ProjectDescription
let project = Project(name: "ConnectionCheck",
    packages: [.package(path: "Modules/Notes")],
    targets: [.target(name: "JibunKit-App", destinations: .iOS, product: .app,
        bundleId: "com.jibunkit.connection-check", deploymentTargets: .iOS("26.0"),
        infoPlist: .default, sources: ["App/**"],
        dependencies: [.package(product: "NotesFeature")])])
'''


def main():
    checker = Path(__file__).with_name("check-feature-connection.py")
    with tempfile.TemporaryDirectory(prefix="jibunkit-connection-") as directory:
        root = Path(directory)
        (root / "Tuist").mkdir()
        sources = root / "Modules/Notes/Sources/NotesFeature"
        sources.mkdir(parents=True)
        (sources / "Notes.swift").write_text('public let greeting = "Notes"\n', encoding="utf-8")
        (root / "App").mkdir()
        (root / "App/App.swift").write_text("import NotesFeature\n", encoding="utf-8")

        def check(label, project=PROJECT, package=PACKAGE, expected=None):
            (root / "Project.swift").write_text(project, encoding="utf-8")
            (root / "Modules/Notes/Package.swift").write_text(package, encoding="utf-8")
            result = subprocess.run([sys.executable, str(checker), "--project", str(root),
                                     "--package", "Modules/Notes", "--product", "NotesFeature"],
                                    capture_output=True, text=True, encoding="utf-8")
            output = result.stdout + result.stderr
            if expected is None:
                valid = result.returncode == 0 and "Declared connection passed" in output
            else:
                valid = result.returncode != 0 and expected in output
            if not valid:
                raise RuntimeError(f"Unexpected result for {label}:\n{output}")
            print(f"passed: {label}")

        check("complete native declarations")
        check("missing project package path", project=PROJECT.replace('packages: [.package(path: "Modules/Notes")]',
                                                                     'packages: []'), expected="Package path missing")
        check("product name mismatch", package=PACKAGE.replace('.library(name: "NotesFeature"',
                                                              '.library(name: "NotesRenamed"'), expected="Library product")
        check("library target missing", package=PACKAGE.replace('.target(name: "NotesFeature")',
                                                               '.target(name: "UnconnectedTarget")'), expected="missing target NotesFeature")
        check("missing app product dependency", project=PROJECT.replace('dependencies: [.package(product: "NotesFeature")]',
                                                                       'dependencies: []'), expected="Host dependency missing")
        check("corrected native declarations")
    print("Native connection diagnostics passed; Xcode and Registry checks remain separate.")


if __name__ == "__main__":
    main()
