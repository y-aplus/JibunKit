"""Build SwiftPM privacy fixtures independently and in Tuist app/widget hosts."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--tuist", default="tuist")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
fixtures = repo / "Tests/PrivacyManifest"

def run(command, cwd, env=None):
    merged = os.environ.copy()
    if env:
        merged.update(env)
    subprocess.run([str(value) for value in command], cwd=cwd, env=merged, check=True)

def read_manifest(path):
    with path.open("rb") as file:
        value = plistlib.load(file)
    assert set(value) == {
        "NSPrivacyTracking", "NSPrivacyTrackingDomains",
        "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes",
    }, (path, value)
    return value

independent = {}
for owner in ["FeatureA", "FeatureB"]:
    package = fixtures / owner
    run(["swift", "build", "--package-path", package], repo)
    manifests = list((package / ".build").rglob("*.bundle/PrivacyInfo.xcprivacy"))
    assert manifests, f"No independent privacy resource bundle for {owner}"
    independent[owner] = read_manifest(manifests[0])

with tempfile.TemporaryDirectory(prefix="jibunkit-privacy-manifest-") as temp:
    temp_root = Path(temp)

    def make_project(label):
        root = temp_root / label
        root.mkdir()
        (root / "Tuist").mkdir()
        for name in ["FeatureA", "FeatureB"]:
            shutil.copytree(fixtures / name, root / name, ignore=shutil.ignore_patterns(".build"))
        shutil.copyfile(fixtures / "App.swift", root / "App.swift")
        shutil.copyfile(fixtures / "Widget.swift", root / "Widget.swift")
        return root

    def configure(root, include_a):
        project = (fixtures / "HostProject.swift.fixture").read_text()
        project = project.replace("__INCLUDE_A__", "true" if include_a else "false")
        (root / "Project.swift").write_text(project)
        run([args.tuist, "generate", "--no-open"], root)

    def build_existing(root, derived):
        run(["xcodebuild", "build", "-workspace", root / "PrivacyHost.xcworkspace",
             "-scheme", "PrivacyHost", "-configuration", "Release",
             "-destination", "generic/platform=iOS", "-derivedDataPath", derived,
             "CODE_SIGNING_ALLOWED=NO"], root)
        apps = list((derived / "Build/Products/Release-iphoneos").glob("PrivacyHost.app"))
        assert len(apps) == 1, apps
        app = apps[0]
        widgets = list(app.glob("PlugIns/PrivacyHostWidget.appex"))
        assert len(widgets) == 1, widgets
        direct = list(app.glob("*.bundle/PrivacyInfo.xcprivacy"))
        widget = list(widgets[0].glob("*.bundle/PrivacyInfo.xcprivacy"))
        return {path.parent.name: (path, read_manifest(path)) for path in direct}, {
            path.parent.name: (path, read_manifest(path)) for path in widget
        }

    def build(include_a, label):
        root = make_project(label)
        configure(root, include_a)
        return build_existing(root, root / f"Build-{label}")

    both_app, both_widget = build(True, "both")
    b_app, b_widget = build(False, "b-only")
    assert len(both_app) == 2, both_app
    assert len(both_widget) == 1, both_widget
    assert len(b_app) == 1, b_app
    assert len(b_widget) == 1, b_widget
    assert all("FeatureA" not in name for name in b_app), b_app
    both_a = next(value for name, value in both_app.items() if "FeatureA" in name)
    both_b = next(value for name, value in both_app.items() if "FeatureB" in name)
    removed_b = next(value for name, value in b_app.items() if "FeatureB" in name)
    assert both_a[1] == independent["FeatureA"]
    assert both_b[1] == independent["FeatureB"]
    assert removed_b[1] == independent["FeatureB"]
    assert next(iter(both_widget.values()))[1] == independent["FeatureB"]
    assert next(iter(b_widget.values()))[1] == independent["FeatureB"]
    assert both_b[1] == removed_b[1]
    assert both_b[0].read_bytes() == removed_b[0].read_bytes()
    assert next(iter(both_widget.values()))[1] == next(iter(b_widget.values()))[1]

    incremental_root = make_project("incremental")
    incremental_derived = incremental_root / "Build-incremental"
    configure(incremental_root, True)
    incremental_both_app, incremental_both_widget = build_existing(
        incremental_root, incremental_derived)
    incremental_before_b_bytes = next(
        value for name, value in incremental_both_app.items() if "FeatureB" in name
    )[0].read_bytes()
    configure(incremental_root, False)
    incremental_b_app, incremental_b_widget = build_existing(
        incremental_root, incremental_derived)
    assert len(incremental_both_app) == 2, incremental_both_app
    assert len(incremental_both_widget) == 1, incremental_both_widget
    assert len(incremental_b_app) == 1, incremental_b_app
    assert len(incremental_b_widget) == 1, incremental_b_widget
    assert all("FeatureA" not in name for name in incremental_b_app), incremental_b_app
    incremental_after_b = next(iter(incremental_b_app.values()))
    assert incremental_after_b[1] == independent["FeatureB"]
    assert incremental_before_b_bytes == incremental_after_b[0].read_bytes()
    assert next(iter(incremental_b_widget.values()))[1] == independent["FeatureB"]
    print("Privacy manifests verified: independent and clean ownership plus same-root incremental A removal preserves B")
