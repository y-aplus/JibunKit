"""Verify native Tuist helpers and a generated/built/signed probe, on macOS CI."""
import argparse
import os
import platform
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--tuist-runtime", type=Path, required=True)
parser.add_argument("--build-probe", action="store_true")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
frameworks = list(args.tuist_runtime.rglob("ProjectDescription.framework"))
if len(frameworks) != 1:
    raise SystemExit(f"Expected one native ProjectDescription framework, found {len(frameworks)}")
framework_parent = frameworks[0].parent
helpers = repo / "Tuist/ProjectDescriptionHelpers"
log_path = Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir())) / "feature-build-requirements.log"

def run(command, cwd=repo):
    with log_path.open("a", encoding="utf-8") as log:
        log.write("\nRUN " + " ".join(map(str, command)) + "\n")
        log.flush()
        result = subprocess.run(list(map(str, command)), cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print("\n".join(log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-100:]))
        raise SystemExit(result.returncode)

with tempfile.TemporaryDirectory(prefix="jibunkit-build-requirements-") as temp:
    root = Path(temp)
    executable = root / "checks"
    run(["swiftc", "-swift-version", "6", "-target", f"{platform.machine()}-apple-macosx{platform.mac_ver()[0]}",
         "-F", framework_parent, "-framework", "ProjectDescription",
         "-Xlinker", "-rpath", "-Xlinker", framework_parent,
         helpers / "FeatureBuildRequirements.swift", helpers / "EnabledFeatureBuildRequirements.swift",
         repo / "Tests/BuildRequirements/main.swift", "-o", executable])
    run([executable])
    print("Native Tuist requirement merge/validation checks passed")
    if not args.build_probe:
        raise SystemExit(0)
    shutil.copytree(helpers, root / "Tuist/ProjectDescriptionHelpers")
    for name in ["Project.swift", "App.swift", "Widget.swift"]:
        source = name + ".fixture" if name == "Project.swift" else name
        shutil.copyfile(repo / "Tests/BuildRequirements" / source, root / name)
    run(["tuist", "generate", "--no-open"], cwd=root)
    run(["xcodebuild", "build", "-workspace", root / "BuildRequirementProbe.xcworkspace",
         "-scheme", "BuildRequirementProbe", "-configuration", "Release", "-destination", "generic/platform=iOS",
         "-derivedDataPath", root / "Build", "CODE_SIGNING_ALLOWED=NO"], cwd=root)
    apps = list((root / "Build/Build/Products/Release-iphoneos").glob("*.app"))
    if len(apps) != 1:
        raise SystemExit(f"Expected one built probe app, found {len(apps)}")
    app = apps[0]
    with (app / "Info.plist").open("rb") as file:
        info = plistlib.load(file)
    assert info["NSCameraUsageDescription"] == "Camera takes photos; Scanner scans documents"
    assert info["UIBackgroundModes"] == ["audio", "processing"]
    assert info["BGTaskSchedulerPermittedIdentifiers"] == ["com.jibunkit.build-scanner.refresh"]
    readback = root / "bundle-readback"
    run(["swiftc", repo / "Tests/BuildRequirements/BundleReadback.swift", "-o", readback])
    run([readback, app, "en", "NSCameraUsageDescription", "Use camera to scan documents"])
    run([readback, app, "ja", "NSCameraUsageDescription", "カメラで書類を撮影します"])
    extensions = list(app.glob("PlugIns/*.appex"))
    assert len(extensions) == 1, extensions
    widget = extensions[0]
    run([readback, widget, "en", "CFBundleDisplayName", "Build Probe Widget"])
    run([readback, widget, "ja", "CFBundleDisplayName", "ビルド検証ウィジェット"])
    app_localizations = {path.name for path in app.glob("*.lproj")}
    widget_localizations = {path.name for path in widget.glob("*.lproj")}
    assert {"en.lproj", "ja.lproj"} <= app_localizations
    assert {"en.lproj", "ja.lproj"} <= widget_localizations
    entitlements = list((root / "Derived").rglob("BuildRequirementProbe.entitlements"))
    assert len(entitlements) == 1, entitlements
    run(["codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der",
         "--entitlements", entitlements[0], app])
    run(["codesign", "--verify", "--strict", app])
    signed = subprocess.run(["codesign", "--display", "--entitlements", ":-", str(app)],
                            capture_output=True, check=True).stdout
    assert plistlib.loads(signed)["com.apple.security.application-groups"] == [
        "group.com.jibunkit.build-camera", "group.com.jibunkit.shared"]
    print("Built Info.plist and ad-hoc signed entitlements preserve composed Feature requirements")
