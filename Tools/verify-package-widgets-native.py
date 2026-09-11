"""Compare package-owned Widgets in standalone and combined native extensions."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--simulator-id", required=True)
parser.add_argument("--tuist", default="tuist")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
fixtures = repo / "Tests/PackageWidgets"
evidence = Path(os.environ["RUNNER_TEMP"]) / "PackageWidgets"
evidence.mkdir(exist_ok=True)


def run(command, cwd, capture=False, check=True):
    return subprocess.run(
        [str(part) for part in command], cwd=cwd, check=check,
        text=True, stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )


with tempfile.TemporaryDirectory(prefix="jibunkit-package-widgets-") as temp:
    root = Path(temp)
    shutil.copytree(fixtures, root, dirs_exist_ok=True)
    (root / "Tuist").mkdir()
    package_path = str(repo).replace("\\", "/")
    for manifest in [root / "FeatureA/Package.swift", root / "FeatureB/Package.swift"]:
        manifest.write_text(
            manifest.read_text().replace("__JIBUNKIT_PATH__", package_path),
            encoding="utf-8",
        )
    (root / "Project.swift.fixture").rename(root / "Project.swift")
    run([args.tuist, "generate", "--no-open"], root)
    derived = root / "DerivedBuild"
    expected = {
        "StandaloneA": {"com.jibunkit.fixture.feature-a.widget"},
        "StandaloneB": {"com.jibunkit.fixture.feature-b.widget"},
        "Combined": {
            "com.jibunkit.fixture.feature-a.widget",
            "com.jibunkit.fixture.feature-b.widget",
        },
    }
    report = {}
    for scheme, expected_kinds in expected.items():
        build = run([
            "xcodebuild", "build", "-workspace", "PackageWidgets.xcworkspace",
            "-scheme", scheme, "-configuration", "Release",
            "-destination", "generic/platform=iOS", "-derivedDataPath", derived,
            "CODE_SIGNING_ALLOWED=NO",
        ], root, capture=True, check=False)
        print(build.stdout, end="")
        (evidence / f"{scheme}-build.log").write_text(build.stdout, encoding="utf-8")
        if build.returncode != 0:
            raise subprocess.CalledProcessError(build.returncode, build.args)
        app = derived / f"Build/Products/Release-iphoneos/{scheme}.app"
        extensions = list((app / "PlugIns").glob("*.appex"))
        assert len(extensions) == 1, f"{scheme} embedded extensions: {extensions}"
        extension = extensions[0]
        with (app / "Info.plist").open("rb") as stream:
            app_info = plistlib.load(stream)
        with (extension / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        assert info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
        assert info["CFBundleIdentifier"] == f'{app_info["CFBundleIdentifier"]}.Widget'
        executable = extension / info["CFBundleExecutable"]
        strings = run(["strings", executable], root, capture=True).stdout
        present = {kind for kinds in expected.values() for kind in kinds if kind in strings}
        assert present == expected_kinds, (scheme, present, expected_kinds)
        copied = evidence / scheme
        copied.mkdir()
        shutil.copyfile(extension / "Info.plist", copied / "Info.plist")
        (copied / "binary-strings.txt").write_text(strings, encoding="utf-8")
        report[scheme] = {
            "hostBundleIdentifier": app_info["CFBundleIdentifier"],
            "host": app.name,
            "extensionBundleIdentifier": info["CFBundleIdentifier"],
            "extensionCount": len(extensions),
            "extension": extension.name,
            "widgetKinds": sorted(present),
        }

    assert report["Combined"]["extensionCount"] == 1
    assert set(report["Combined"]["widgetKinds"]) == (
        set(report["StandaloneA"]["widgetKinds"]) |
        set(report["StandaloneB"]["widgetKinds"])
    )
    (evidence / "comparison.json").write_text(
        json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print("Native Widget extensions: standalone A/B and one combined extension preserve package kinds")

    result_bundle = evidence / "TimelineTests.xcresult"
    result = run([
        "xcodebuild", "test", "-workspace", "PackageWidgets.xcworkspace",
        "-scheme", "TimelineTests", "-configuration", "Debug",
        "-destination", f"platform=iOS Simulator,id={args.simulator_id}",
        "-derivedDataPath", root / "SimulatorBuild",
        "-resultBundlePath", result_bundle,
        "-only-testing:TimelineTests/TimelineTests/testPackageTimelinesRemainOwnerScoped",
        "-parallel-testing-enabled", "NO",
        "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual",
    ], root, capture=True, check=False)
    print(result.stdout, end="")
    (evidence / "timeline-tests.log").write_text(result.stdout, encoding="utf-8")
    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, result.args)
    assert "testPackageTimelinesRemainOwnerScoped]' passed" in result.stdout
    assert "** TEST SUCCEEDED **" in result.stdout
    print("Package Timeline providers: identical local key names remain owner-prefixed and isolated")
