"""Build/test a combined native Feature host and package one diagnostic IPA.

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


def require_test_passes(report, summary, sources):
    expected = []
    for source in sources:
        classes = re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase", source)
        methods = re.findall(r"\bfunc\s+(test\w+)\s*\(", source)
        if len(classes) != 1 or not methods or len(methods) != len(set(methods)):
            raise ValueError("Expected one XCTestCase with unique test methods per media test source")
        expected.extend((classes[0], method) for method in methods)
    if not expected or len(expected) != len(set(expected)):
        raise ValueError("Missing or duplicate media tests")
    cases = []
    def visit(nodes):
        for node in nodes:
            if node.get("nodeType") == "Test Case":
                identity = node.get("nodeIdentifier", "").split("/")
                if len(identity) < 2:
                    raise ValueError("Test case has no class/method identifier")
                cases.append((identity[-2], identity[-1].removesuffix("()"), node.get("result")))
            else:
                visit(node.get("children", []))
    visit(report.get("testNodes", []))
    for name, method in expected:
        actual = [status for cls, test, status in cases if (cls, test) == (name, method)]
        if actual != ["Passed"]:
            raise ValueError(f"Expected one actual passing test: {name}.{method}: {actual}")
    if (summary.get("result") != "Passed" or summary.get("failedTests") != 0
            or summary.get("skippedTests") != 0 or summary.get("passedTests") != len(expected)
            or len(cases) != len(expected)):
        raise ValueError("Native media summary contains failure, skip, missing or unexpected tests")
    return [f"{name}.{method}" for name, method in expected]


def check_requirements(info, surface="media"):
    if surface not in {"media", "background-location"}:
        raise ValueError("Unknown native host surface")
    descriptions = (["NSCameraUsageDescription", "NSMicrophoneUsageDescription"] if surface == "media"
                    else ["NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"])
    for key in descriptions:
        if not isinstance(info.get(key), str) or not info[key].strip():
            raise ValueError(f"Missing media usage description: {key}")
    modes = {"audio"} if surface == "media" else {"fetch", "processing", "location"}
    if not modes <= set(info.get("UIBackgroundModes", [])):
        raise ValueError("Missing required background modes")
    if surface == "background-location":
        required = {"com.jibunkit.app.p2-background-a.ordinary",
                    "com.jibunkit.app.p2-background-b.ordinary",
                    "com.jibunkit.app.p2-background.shared-refresh",
                    "com.jibunkit.app.p2-background-a.export",
                    "com.jibunkit.app.p2-background-b.export"}
        if set(info.get("BGTaskSchedulerPermittedIdentifiers", [])) != required:
            raise ValueError("Background task identifiers differ from the diagnostic contract")
    if info.get("CFBundleIdentifier") != "com.jibunkit.app":
        raise ValueError("Diagnostic app identity changed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator-id", required=True)
    parser.add_argument("--surface", choices=["media", "background-location"], default="media")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    is_media = args.surface == "media"
    families = ["MediaAudio", "MediaCapture", "MediaIntegration"] if is_media else ["P2Background", "P2Location"]
    scheme = "MediaNativeTests" if is_media else "BackgroundLocationNativeTests"
    evidence = Path(os.environ["RUNNER_TEMP"]) / ("Media" if is_media else "BackgroundLocation")
    evidence.mkdir(exist_ok=True)
    source = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    started = time.monotonic()
    timings = []

    def run(command, cwd, label, limit=900):
        remaining = 24 * 60 - (time.monotonic() - started)
        if remaining <= 0:
            raise TimeoutError("Native host validation exhausted its 24 minute step budget")
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

    result = {"source": source, "surface": args.surface, "passed": False,
              "physical_os_actions": "not exercised; grouped device verification required"}
    try:
        with tempfile.TemporaryDirectory(prefix=f"jibunkit-{args.surface}-") as temporary:
            root = Path(temporary)
            # Ignored local Features, data and worktree-private files stay out.
            names = subprocess.check_output(["git", "ls-files", "-z"], cwd=repo).decode().split("\0")
            for name in filter(None, names):
                destination = root / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(repo / name, destination)
            prepare = "prepare-media-host.py" if is_media else "prepare-background-location-host.py"
            run(["python3", root / "Tools" / prepare, "--host", root], root, "prepare")
            run(["tuist", "generate", "--no-open"], root, "generate")
            derived = root / "Build"
            common = ["-workspace", "JibunKit.xcworkspace", "-derivedDataPath", derived]
            native_error = None
            try:
                run(["xcodebuild", "test", *common, "-scheme", scheme,
                       "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={args.simulator_id}",
                       "-resultBundlePath", evidence / "native-tests.xcresult",
                       f"-only-testing:{scheme}", "-parallel-testing-enabled", "NO",
                       "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual"], root, "native-tests")
            except subprocess.CalledProcessError as error:
                native_error = error
            finally:
                # Console output can be interleaved with AVFoundation diagnostics.
                # Export structured results even on failure; retain the original error.
                for section in ["tests", "summary"]:
                    try:
                        output = run(["xcrun", "xcresulttool", "get", "test-results", section,
                                      "--path", evidence / "native-tests.xcresult"], root,
                                     f"test-{section}", limit=60)
                        (evidence / f"test-{section}.json").write_text(output, encoding="utf-8")
                    except Exception as export_error:
                        result[f"{section}_export_error"] = str(export_error)
            if native_error is not None:
                try:
                    run(["xcrun", "xcresulttool", "export", "diagnostics", "--path",
                         evidence / "native-tests.xcresult", "--output-path", evidence / "crash-diagnostics"],
                        root, "export-diagnostics", limit=90)
                except Exception as export_error:
                    result["diagnostics_export_error"] = str(export_error)
                raise native_error
            result["tests"] = require_test_passes(
                json.loads((evidence / "test-tests.json").read_text(encoding="utf-8")),
                json.loads((evidence / "test-summary.json").read_text(encoding="utf-8")), [

                (root / f"Tests/{family}/{family}NativeTests.swift").read_text(encoding="utf-8")
                for family in families])
            run(["xcodebuild", "build", *common, "-scheme", "JibunKit-App",
                 "-configuration", "Release", "-destination", "generic/platform=iOS",
                 "CODE_SIGNING_ALLOWED=NO"], root, "release-build")
            app = derived / "Build/Products/Release-iphoneos/JibunKit_App.app"
            info = plistlib.loads((app / "Info.plist").read_bytes())
            check_requirements(info, args.surface)
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
            ipa = evidence / ("JibunKit-P2-C-check.ipa" if is_media else "JibunKit-P2-B-check.ipa")
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
