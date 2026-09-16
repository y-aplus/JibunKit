"""P2-L native comparison or ordinary-host integration, one parallel CI boundary.

Every subprocess leaves a log and timing record, including timeout/failure.
These tests do not prove physical Live Activity/Alarm presentation or OS taps.
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
import time


FAMILIES = {
    "live": {"directory": "ContinuingLiveActivities", "schemes": ["StandaloneA", "StandaloneB", "Combined"],
             "modules": ["ContinuingFeatureA", "ContinuingFeatureB"], "tests": "ContinuingLiveActivityNativeTests"},
    "alarm": {"directory": "ContinuingAlarms", "schemes": ["StandaloneA", "StandaloneB", "Combined"],
              "modules": ["ContinuingAlarmFeatureA", "ContinuingAlarmFeatureB"], "tests": "ContinuingAlarmNativeTests"},
}


def check_owner_metadata(metadata, modules, included):
    actions = metadata.get("actions")
    if not isinstance(actions, dict):
        raise ValueError("Missing native App Intents actions")
    identities = [value.get("fullyQualifiedTypeName", "") for value in actions.values()]
    for module in modules:
        present = any(name.startswith(module + ".") for name in identities)
        if present != (module in included):
            raise ValueError(f"Native owner metadata mismatch: {module}, expected={module in included}")


def require_test_passes(log, source):
    methods = re.findall(r"\bfunc\s+(test\w+)\s*\(", source)
    if not methods or len(methods) != len(set(methods)):
        raise ValueError("Missing or duplicate XCTest method declarations")
    for method in methods:
        passed = re.findall(rf"Test Case '-\[[^\]]+ {re.escape(method)}\]' passed", log)
        if len(passed) != 1:
            raise ValueError(f"Expected exactly one actual passing XCTest: {method}, got {len(passed)}")
    if "** TEST SUCCEEDED **" not in log:
        raise ValueError("Native tests did not finish successfully")
    return methods


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["live", "alarm", "host"], required=True)
    parser.add_argument("--simulator-id", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    evidence = Path(os.environ["RUNNER_TEMP"]) / f"Continuing-{args.mode}"
    evidence.mkdir(exist_ok=True)
    source = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    started = time.monotonic()
    timings = []

    def run(command, cwd, label, limit=900):
        # Leave time for workflow setup and artifact upload within the 30m job.
        remaining = 24 * 60 - (time.monotonic() - started)
        if remaining <= 0:
            raise TimeoutError("P2-L verification exhausted its 24 minute step budget")
        begin = time.monotonic()
        output = ""
        code = None
        try:
            result = subprocess.run([str(value) for value in command], cwd=cwd,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=min(limit, remaining))
            output = result.stdout
            code = result.returncode
            result.check_returncode()
            return output
        except subprocess.TimeoutExpired as error:
            output = error.stdout or ""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            raise
        finally:
            (evidence / f"{label}.log").write_text(output, encoding="utf-8")
            timings.append({"label": label, "seconds": round(time.monotonic() - begin, 3), "exit_code": code})
            (evidence / "timings.json").write_text(json.dumps(timings, indent=2) + "\n")
            print(output, end="", flush=True)

    def build(root, workspace, scheme, derived):
        run(["xcodebuild", "build", "-workspace", workspace, "-scheme", scheme,
             "-configuration", "Release", "-destination", "generic/platform=iOS",
             "-derivedDataPath", derived, "CODE_SIGNING_ALLOWED=NO"], root, f"{scheme}-build")

    def test(root, workspace, scheme, derived, selection, declaration, label):
        log = run(["xcodebuild", "test", "-workspace", workspace, "-scheme", scheme,
                   "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={args.simulator_id}",
                   "-derivedDataPath", derived, "-resultBundlePath", evidence / f"{label}.xcresult",
                   f"-only-testing:{selection}", "-parallel-testing-enabled", "NO",
                   "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual"], root, label)
        passed = require_test_passes(log, declaration.read_text(encoding="utf-8"))
        (evidence / f"{label}-passed.json").write_text(json.dumps(passed, indent=2) + "\n")

    def metadata(app, owners, modules, label):
        extensions = list((app / "PlugIns").glob("*.appex"))
        widgets = [path for path in extensions if plistlib.loads((path / "Info.plist").read_bytes())
                   .get("NSExtension", {}).get("NSExtensionPointIdentifier") == "com.apple.widgetkit-extension"]
        if len(widgets) != 1:
            raise ValueError(f"Expected one embedded Widget extension: {widgets}")
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if info.get("NSSupportsLiveActivities") is not True:
            raise ValueError("Live Activities plist requirement missing")
        if args.mode in {"alarm", "host"} and not info.get("NSAlarmKitUsageDescription", "").strip():
            raise ValueError("AlarmKit usage description missing")
        paths = {}
        for bundle, kind in [(app, "app"), (widgets[0], "widget")]:
            path = bundle / "Metadata.appintents/extract.actionsdata"
            check_owner_metadata(json.loads(path.read_bytes()), modules, owners)
            copy = evidence / f"{label}-{kind}-actionsdata.json"
            shutil.copyfile(path, copy)
            shutil.copyfile(bundle / "Info.plist", evidence / f"{label}-{kind}-Info.plist")
            paths[kind] = copy
        return paths

    def compare(baselines, integrated, root, label):
        command = ["python3", repo / "Tools/verify-app-intents-integration.py"]
        for path in baselines:
            command += ["--baseline", path]
        run(command + ["--integrated", integrated], root, label)

    try:
        with tempfile.TemporaryDirectory(prefix=f"jibunkit-continuing-{args.mode}-") as temporary:
            root = Path(temporary)
            derived = root / "Build"
            if args.mode in FAMILIES:
                family = FAMILIES[args.mode]
                shutil.copytree(repo / "Tests" / family["directory"], root, dirs_exist_ok=True)
                (root / "Tuist").mkdir(exist_ok=True)
                for path in [root / "Project.swift.fixture", *root.rglob("Package.swift")]:
                    path.write_text(path.read_text(encoding="utf-8").replace("__JIBUNKIT_PATH__", repo.as_posix()), encoding="utf-8")
                (root / "Project.swift.fixture").rename(root / "Project.swift")
                run(["tuist", "generate", "--no-open"], root, "generate")
                workspace = family["directory"] + ".xcworkspace"
                collected = []
                for index, scheme in enumerate(family["schemes"]):
                    build(root, workspace, scheme, derived)
                    owners = family["modules"] if index == 2 else [family["modules"][index]]
                    collected.append(metadata(derived / f"Build/Products/Release-iphoneos/{scheme}.app",
                                              owners, family["modules"], scheme))
                for kind in ["app", "widget"]:
                    compare([row[kind] for row in collected[:2]], collected[2][kind], root, f"compare-{kind}")
                compare([collected[2]["widget"]], collected[2]["app"], root, "widget-app")
                test(root, workspace, family["tests"], derived, family["tests"], root / "NativeTests.swift", "native-tests")
            else:
                # Tracked files only: ignored Zaiko sources and local data stay out.
                for name in filter(None, subprocess.check_output(["git", "ls-files", "-z"], cwd=repo).decode().split("\0")):
                    destination = root / name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(repo / name, destination)
                run(["python3", root / "Tools/prepare-continuing-surfaces-host.py", "--host", root], root, "prepare")
                run(["tuist", "generate", "--no-open"], root, "generate")
                build(root, "JibunKit.xcworkspace", "JibunKit-App", derived)
                test(root, "JibunKit.xcworkspace", "MigrationUITests", derived,
                     "MigrationUITests/ContinuingHostUITests", root / "UITests/ContinuingHostUITests.swift", "host-tests")
                app = derived / "Build/Products/Release-iphoneos/JibunKit_App.app"
                modules = FAMILIES["live"]["modules"] + FAMILIES["alarm"]["modules"]
                paths = metadata(app, modules, modules, "host")
                compare([paths["widget"]], paths["app"], root, "widget-host")
                entitlements = root / "Derived"

                def entitlement(name):
                    matches = list(entitlements.rglob(name))
                    if len(matches) != 1:
                        raise ValueError(f"Expected one entitlement file: {name}: {matches}")
                    return matches[0]

                run(["codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der",
                     "--entitlements", entitlement("JibunKitWidget-Extension.entitlements"),
                     app / "PlugIns/JibunKitWidget_Extension.appex"], root, "sign-widget")
                run(["python3", root / "Tools/verify-share-extension.py", "--app", app,
                     "--entitlements-root", entitlements], root, "sign-share")
                run(["codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der",
                     "--entitlements", entitlement("JibunKit-App.entitlements"), app], root, "sign-app")
                run(["codesign", "--verify", "--deep", "--strict", app], root, "verify-signatures")
                payload = root / "Package/Payload"
                payload.mkdir(parents=True)
                run(["ditto", app, payload / "JibunKit.app"], root, "copy-payload")
                ipa = evidence / "JibunKit-P2-L-check.ipa"
                run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", "Payload", ipa], payload.parent, "package")
                run(["unzip", "-t", ipa], root, "ipa-crc")
                run(["shasum", "--algorithm", "256", ipa], root, "ipa-sha256")
            (evidence / "result.json").write_text(json.dumps({"mode": args.mode, "source": source, "passed": True,
                "physical_os_actions": "pending grouped physical verification"}, indent=2) + "\n")
    except Exception as error:
        (evidence / "result.json").write_text(json.dumps({"mode": args.mode, "source": source,
            "passed": False, "error": str(error)}, indent=2) + "\n")
        raise


if __name__ == "__main__":
    main()
