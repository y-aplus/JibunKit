"""Build/test the combined P2-C host and package one diagnostic IPA.

No camera, microphone, lock-screen command, or background behavior is inferred
from simulator success. The result explicitly leaves those device checks open.
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


def require_test_passes(log, sources):
    expected = []
    for source in sources:
        classes = re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase", source)
        methods = re.findall(r"\bfunc\s+(test\w+)\s*\(", source)
        if len(classes) != 1 or not methods or len(methods) != len(set(methods)):
            raise ValueError("Expected one XCTestCase with unique test methods per media test source")
        expected.extend((classes[0], method) for method in methods)
    if not expected or len(expected) != len(set(expected)):
        raise ValueError("Missing or duplicate media tests")
    for name, method in expected:
        pattern = rf"Test Case '-\[(?:\w+\.)?{re.escape(name)} {re.escape(method)}\]' passed"
        if len(re.findall(pattern, log)) != 1:
            raise ValueError(f"Expected one actual passing test: {name}.{method}")
    if "** TEST SUCCEEDED **" not in log:
        raise ValueError("Native media tests did not finish successfully")
    return [f"{name}.{method}" for name, method in expected]


def check_requirements(info):
    for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription"]:
        if not isinstance(info.get(key), str) or not info[key].strip():
            raise ValueError(f"Missing media usage description: {key}")
    if "audio" not in info.get("UIBackgroundModes", []):
        raise ValueError("Missing audio background mode")
    if info.get("CFBundleIdentifier") != "com.jibunkit.app":
        raise ValueError("Diagnostic app identity changed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator-id", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    evidence = Path(os.environ["RUNNER_TEMP"]) / "Media"
    evidence.mkdir(exist_ok=True)
    source = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    started = time.monotonic()
    timings = []

    def run(command, cwd, label, limit=900):
        remaining = 24 * 60 - (time.monotonic() - started)
        if remaining <= 0:
            raise TimeoutError("Media validation exhausted its 24 minute step budget")
        begin, output, code = time.monotonic(), "", None
        try:
            result = subprocess.run([str(value) for value in command], cwd=cwd,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=min(limit, remaining))
            output, code = result.stdout, result.returncode
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
            (evidence / "timings.json").write_text(json.dumps(timings, indent=2) + "\n", encoding="utf-8")
            print(output, end="", flush=True)

    result = {"source": source, "passed": False,
              "physical_os_actions": "not exercised; grouped device verification required"}
    try:
        with tempfile.TemporaryDirectory(prefix="jibunkit-media-") as temporary:
            root = Path(temporary)
            # Ignored local Features, data and worktree-private files stay out.
            names = subprocess.check_output(["git", "ls-files", "-z"], cwd=repo).decode().split("\0")
            for name in filter(None, names):
                destination = root / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(repo / name, destination)
            run(["python3", root / "Tools/prepare-media-host.py", "--host", root], root, "prepare")
            run(["tuist", "generate", "--no-open"], root, "generate")
            derived = root / "Build"
            common = ["-workspace", "JibunKit.xcworkspace", "-derivedDataPath", derived]
            log = run(["xcodebuild", "test", *common, "-scheme", "MediaNativeTests",
                       "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={args.simulator_id}",
                       "-resultBundlePath", evidence / "native-tests.xcresult",
                       "-only-testing:MediaNativeTests", "-parallel-testing-enabled", "NO",
                       "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual"], root, "native-tests")
            result["tests"] = require_test_passes(log, [
                (root / f"Tests/{family}/{family}NativeTests.swift").read_text(encoding="utf-8")
                for family in ["MediaAudio", "MediaCapture"]])
            run(["xcodebuild", "build", *common, "-scheme", "JibunKit-App",
                 "-configuration", "Release", "-destination", "generic/platform=iOS",
                 "CODE_SIGNING_ALLOWED=NO"], root, "release-build")
            app = derived / "Build/Products/Release-iphoneos/JibunKit_App.app"
            info = plistlib.loads((app / "Info.plist").read_bytes())
            check_requirements(info)
            shutil.copyfile(app / "Info.plist", evidence / "app-Info.plist")

            def entitlement(name):
                matches = list((root / "Derived").rglob(name))
                if len(matches) != 1:
                    raise ValueError(f"Expected one entitlement file: {name}: {matches}")
                return matches[0]

            run(["codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der",
                 "--entitlements", entitlement("JibunKitWidget-Extension.entitlements"),
                 app / "PlugIns/JibunKitWidget_Extension.appex"], root, "sign-widget")
            run(["python3", root / "Tools/verify-share-extension.py", "--app", app,
                 "--entitlements-root", root / "Derived"], root, "sign-share")
            run(["codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der",
                 "--entitlements", entitlement("JibunKit-App.entitlements"), app], root, "sign-app")
            run(["codesign", "--verify", "--deep", "--strict", app], root, "verify-signatures")
            payload = root / "Package/Payload"
            payload.mkdir(parents=True)
            run(["ditto", app, payload / "JibunKit.app"], root, "copy-payload")
            ipa = evidence / "JibunKit-P2-C-check.ipa"
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", "Payload", ipa], payload.parent, "package")
            run(["unzip", "-t", ipa], root, "ipa-crc")
            run(["shasum", "--algorithm", "256", ipa], root, "ipa-sha256")
            result["passed"] = True
    except Exception as error:
        result["error"] = str(error)
        raise
    finally:
        (evidence / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
