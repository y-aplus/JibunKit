"""Test shared refresh on iOS, then compare (or only build) native BGTaskScheduler."""
import argparse
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--simulator-id", required=True)
parser.add_argument("--tuist", default="tuist")
parser.add_argument("--build-only", action="store_true")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
fixture = repo / "Tests/BackgroundTasksNative"

with tempfile.TemporaryDirectory(prefix="jibunkit-backgroundtasks-native-") as temp:
    root = Path(temp)
    (root / "Tuist").mkdir()
    project = (fixture / "Project.swift.fixture").read_text()
    project = project.replace("__JIBUNKIT_PATH__", str(repo).replace("\\", "/"))
    (root / "Project.swift").write_text(project)
    shutil.copyfile(fixture / "App.swift", root / "App.swift")
    shutil.copyfile(fixture / "UITests.swift", root / "UITests.swift")
    (root / "SharedRefreshTests").mkdir()
    test_sources = [
        "MiniAppSharedRefreshTests.swift", "MiniAppSharedRefreshJournalTests.swift",
    ]
    for source in test_sources:
        shutil.copyfile(repo / "Tests/JibunKitCoreTests" / source, root / "SharedRefreshTests" / source)
    subprocess.run([args.tuist, "generate", "--no-open"], cwd=root, check=True)
    unit_command = [
        "xcodebuild", "test", "-workspace", "BackgroundTasksNative.xcworkspace",
        "-scheme", "SharedRefreshTests", "-configuration", "Debug",
        "-destination", f"platform=iOS Simulator,id={args.simulator_id}",
        "-derivedDataPath", str(root / "DerivedData"),
        "-resultBundlePath", str(Path(os.environ["RUNNER_TEMP"]) / "SharedRefresh.xcresult"),
        "-parallel-testing-enabled", "NO",
        "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual",
    ]
    unit_result = subprocess.run(
        unit_command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(unit_result.stdout, end="")
    (Path(os.environ["RUNNER_TEMP"]) / "shared-refresh-xcodebuild.log").write_text(unit_result.stdout)
    if unit_result.returncode != 0:
        raise subprocess.CalledProcessError(unit_result.returncode, unit_command)
    if "** TEST SUCCEEDED **" not in unit_result.stdout:
        raise RuntimeError("Shared refresh iOS tests did not succeed")
    # A green runner with no selected tests is not evidence. Require each method
    # from the copied sources, including persistence/center integration tests.
    for source in test_sources:
        methods = re.findall(r"func (test\w+)\(", (root / "SharedRefreshTests" / source).read_text())
        if not methods:
            raise RuntimeError(f"No shared refresh tests found in {source}")
        for method in methods:
            if not re.search(rf"Test Case '-\[.* {re.escape(method)}\]' passed", unit_result.stdout):
                raise RuntimeError(f"Shared refresh test did not report passed: {method}")
    print("Shared refresh iOS journal/batch tests passed with injected scheduler; not OS launch evidence")
    subprocess.run([
        "xcrun", "simctl", "uninstall", args.simulator_id,
        "com.jibunkit.backgroundtasks-native",
    ], check=False)
    method = "testTwoOwnersMatchNativePendingRequestsAndCancellationIsScoped"
    identifier = f"BackgroundTasksNativeUITests/BackgroundTasksNativeUITests/{method}"
    action = "build-for-testing" if args.build_only else "test"
    command = [
        "xcodebuild", action,
        "-workspace", "BackgroundTasksNative.xcworkspace",
        "-scheme", "BackgroundTasksNative",
        "-destination", f"platform=iOS Simulator,id={args.simulator_id}",
        "-derivedDataPath", str(root / "DerivedData"),
        "-parallel-testing-enabled", "NO",
    ]
    if not args.build_only:
        command.extend([
            "-resultBundlePath",
            str(Path(os.environ["RUNNER_TEMP"]) / "BackgroundTasksNative.xcresult"),
            f"-only-testing:{identifier}",
        ])
    result = subprocess.run(
        command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(result.stdout, end="")
    (Path(os.environ["RUNNER_TEMP"]) / "backgroundtasks-xcodebuild.log").write_text(result.stdout)
    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, command)
    if args.build_only:
        if "** TEST BUILD SUCCEEDED **" not in result.stdout:
            raise RuntimeError("Native BackgroundTasks fixture did not report a successful test build")
    else:
        passed = re.search(rf"(?m)^.*{re.escape(method)}.*passed.*$", result.stdout)
        if not passed or "** TEST SUCCEEDED **" not in result.stdout:
            raise RuntimeError("Focused native BackgroundTasks test did not report passed")

if args.build_only:
    print("Native BackgroundTasks fixture compiled only; native scheduler runtime validation not executed")
else:
    print("Native BackgroundTasks verified: pending request parity and scoped cancellation")
