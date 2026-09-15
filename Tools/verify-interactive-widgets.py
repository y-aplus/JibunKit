"""One P2-W boundary: independent native contracts or normal-host integration.

These two modes run in parallel jobs. Direct Intent XCTest is native adapter
evidence, not a substitute for physical Widget/Control taps and configuration.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile


def assert_owner_metadata(metadata, owners, label):
    """Require each fixture owner's complete native surface, without cross-owner leakage."""
    expected = {
        "actions": ["Increment", "WidgetConfiguration", "ControlConfiguration"],
        "entities": ["Item"],
        "queries": ["Query"],
    }
    fields = {
        "actions": "fullyQualifiedTypeName",
        "entities": "fullyQualifiedTypeName",
        "queries": "fullyQualifiedIdentifier",
    }
    for section, suffixes in expected.items():
        definitions = metadata.get(section)
        assert isinstance(definitions, dict), (label, section, type(definitions).__name__)
        identities = {value.get(fields[section]) for value in definitions.values() if isinstance(value, dict)}
        for owner in "AB":
            for suffix in suffixes:
                identity = f"InteractiveFeature{owner}.Feature{owner}{suffix}"
                assert (identity in identities) == (owner in owners), (label, section, identity)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["native", "host"], required=True)
    parser.add_argument("--simulator-id", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    evidence = Path(os.environ["RUNNER_TEMP"]) / f"Interactive-{args.mode}"
    evidence.mkdir(exist_ok=True)

    def run(command, cwd, label, quiet=False):
        result = subprocess.run([str(p) for p in command], cwd=cwd, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900)
        (evidence / f"{label}.log").write_text(result.stdout, encoding="utf-8")
        if not quiet:
            print(result.stdout, end="", flush=True)
        result.check_returncode()
        return result.stdout

    def build(root, workspace, scheme, derived):
        run(["xcodebuild", "build", "-workspace", workspace, "-scheme", scheme,
             "-configuration", "Release", "-destination", "generic/platform=iOS",
             "-derivedDataPath", derived, "CODE_SIGNING_ALLOWED=NO"], root, f"{scheme}-build")

    def test(root, workspace, scheme, derived, identifier, source, label):
        log = run(["xcodebuild", "test", "-workspace", workspace, "-scheme", scheme,
                   "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={args.simulator_id}",
                   "-derivedDataPath", derived, "-resultBundlePath", evidence / f"{label}.xcresult",
                   f"-only-testing:{identifier}", "-parallel-testing-enabled", "NO",
                   "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual"], root, label)
        methods = re.findall(r"\bfunc\s+(test\w+)\s*\(", source.read_text(encoding="utf-8"))
        assert methods, "No declared test cases"
        assert len(methods) == len(set(methods)), f"Duplicate test declarations: {methods}"
        for method in methods:
            passes = re.findall(rf"Test Case '-\[[^\]]+ {re.escape(method)}\]' passed", log)
            assert len(passes) == 1, (method, len(passes))
        assert "** TEST SUCCEEDED **" in log
        (evidence / f"{label}-passed.json").write_text(json.dumps(methods, indent=2) + "\n")

    def compare(baselines, integrated, label):
        for index, path in enumerate([*baselines, integrated]):
            assert path.is_file(), f"Native metadata absent: {path}"
            shutil.copyfile(path, evidence / f"{label}-{index}-actionsdata.json")
        command = ["python3", repo / "Tools/verify-app-intents-integration.py"]
        for path in baselines:
            command += ["--baseline", path]
        run(command + ["--integrated", integrated], repo, label)

    with tempfile.TemporaryDirectory(prefix=f"jibunkit-interactive-{args.mode}-") as temporary:
        root = Path(temporary)
        derived = root / "Build"
        if args.mode == "native":
            shutil.copytree(repo / "Tests/InteractiveWidgets", root, dirs_exist_ok=True)
            (root / "Tuist").mkdir()
            for path in [root / "Project.swift.fixture", root / "FeatureA/Package.swift", root / "FeatureB/Package.swift"]:
                path.write_text(path.read_text(encoding="utf-8").replace("__JIBUNKIT_PATH__", repo.as_posix()), encoding="utf-8")
            (root / "Project.swift.fixture").rename(root / "Project.swift")
            run(["tuist", "generate", "--no-open"], root, "generate")
            apps = {}
            extensions = {}
            for scheme, owners in [("StandaloneA", "A"), ("StandaloneB", "B"), ("Combined", "AB")]:
                build(root, "InteractiveWidgets.xcworkspace", scheme, derived)
                app = derived / f"Build/Products/Release-iphoneos/{scheme}.app"
                embedded = list((app / "PlugIns").glob("*.appex"))
                assert len(embedded) == 1, (scheme, embedded)
                extension = embedded[0]
                info = plistlib.loads((extension / "Info.plist").read_bytes())
                assert info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
                strings = run(["strings", extension / info["CFBundleExecutable"]], root, f"{scheme}-strings", quiet=True)
                for owner in "AB":
                    for surface in ["widget", "control"]:
                        kind = f"com.jibunkit.fixture.interactive-{owner.lower()}.{surface}"
                        assert (kind in strings) == (owner in owners), (scheme, kind)
                apps[scheme] = app / "Metadata.appintents/extract.actionsdata"
                extensions[scheme] = extension / "Metadata.appintents/extract.actionsdata"
                assert_owner_metadata(json.loads(apps[scheme].read_bytes()), owners, f"{scheme} app")
                assert_owner_metadata(json.loads(extensions[scheme].read_bytes()), owners, f"{scheme} extension")
            for label, paths in [("app", apps), ("extension", extensions)]:
                compare([paths["StandaloneA"], paths["StandaloneB"]], paths["Combined"], f"compare-{label}")
            compare([apps["Combined"]], extensions["Combined"], "app-extension")
            test(root, "InteractiveWidgets.xcworkspace", "InteractiveNativeTests", derived,
                 "InteractiveNativeTests/InteractiveNativeTests", root / "NativeTests.swift", "native-tests")
        else:
            # Only tracked project files. Local ignored Zaiko/data/worktrees do
            # not enter either the diagnostic host or its artifacts.
            paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=repo).decode().split("\0")
            for name in filter(None, paths):
                destination = root / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(repo / name, destination)
            run(["python3", root / "Tools/prepare-interactive-widgets-host.py", "--host", root], root, "prepare")
            run(["tuist", "generate", "--no-open"], root, "generate")
            build(root, "JibunKit.xcworkspace", "JibunKit-App", derived)
            test(root, "JibunKit.xcworkspace", "MigrationUITests", derived,
                 "MigrationUITests/InteractiveManagementUITests", root / "UITests/InteractiveManagementUITests.swift", "host-tests")
            app = derived / "Build/Products/Release-iphoneos/JibunKit_App.app"
            widget = app / "PlugIns/JibunKitWidget_Extension.appex"
            for bundle, label in [(app, "host"), (widget, "widget")]:
                data = bundle / "Metadata.appintents/extract.actionsdata"
                shutil.copyfile(data, evidence / f"{label}-actionsdata.json")
                metadata = json.loads(data.read_bytes())
                for owner in "AB":
                    assert any(value.get("fullyQualifiedTypeName") == f"InteractiveFeature{owner}.Feature{owner}Increment"
                               for value in metadata["actions"].values())
            # The normal app also contains its existing Counter/Reminder
            # intents; require every extension contribution in the app.
            compare([widget / "Metadata.appintents/extract.actionsdata"], app / "Metadata.appintents/extract.actionsdata", "widget-host")
            info = plistlib.loads((app / "Info.plist").read_bytes())
            assert info["CFBundleIdentifier"] == "com.jibunkit.app"
            assert info["CFBundleShortVersionString"] == "0.8.0" and info["CFBundleVersion"] == "10"
            assert {p.name for p in (app / "PlugIns").glob("*.appex")} == {"JibunKitWidget_Extension.appex", "JibunKitShare_Extension.appex"}
            entitlements = root / "Derived"
            def entitlement(name):
                matches = list(entitlements.rglob(name))
                assert len(matches) == 1, matches
                return matches[0]
            run(["codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der",
                 "--entitlements", entitlement("JibunKitWidget-Extension.entitlements"), widget], root, "sign-widget")
            run(["python3", root / "Tools/verify-share-extension.py", "--app", app, "--entitlements-root", entitlements], root, "sign-share")
            run(["codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der",
                 "--entitlements", entitlement("JibunKit-App.entitlements"), app], root, "sign-app")
            run(["codesign", "--verify", "--deep", "--strict", app], root, "verify-signatures")
            payload = root / "Package/Payload"
            payload.mkdir(parents=True)
            run(["ditto", app, payload / "JibunKit.app"], root, "copy-payload")
            ipa = evidence / "JibunKit-P2-W-check.ipa"
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", "Payload", ipa], payload.parent, "package")
            run(["unzip", "-t", ipa], root, "ipa-crc")
            run(["shasum", "--algorithm", "256", ipa], root, "ipa-sha256")
        (evidence / "result.json").write_text(json.dumps({"mode": args.mode, "passed": True,
            "source": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
            "widget_control_os_taps": "pending physical grouped verification"}, indent=2) + "\n")


if __name__ == "__main__":
    main()
