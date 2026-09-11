"""Run native BGTaskScheduler pending-request comparison on iOS Simulator."""
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
    subprocess.run([args.tuist, "generate", "--no-open"], cwd=root, check=True)
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
    print("Native BackgroundTasks fixture compiled only; runtime validation not executed")
else:
    print("Native BackgroundTasks verified: pending request parity and scoped cancellation")
