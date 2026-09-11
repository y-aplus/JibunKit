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
    command = [
        "xcodebuild", "test",
        "-workspace", "BackgroundTasksNative.xcworkspace",
        "-scheme", "BackgroundTasksNative",
        "-destination", f"platform=iOS Simulator,id={args.simulator_id}",
        "-derivedDataPath", str(root / "DerivedData"),
        "-resultBundlePath", str(Path(os.environ["RUNNER_TEMP"]) / "BackgroundTasksNative.xcresult"),
        "-parallel-testing-enabled", "NO",
        f"-only-testing:{identifier}",
    ]
    result = subprocess.run(
        command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(result.stdout, end="")
    (Path(os.environ["RUNNER_TEMP"]) / "backgroundtasks-xcodebuild.log").write_text(result.stdout)
    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, command)
    passed = re.search(rf"(?m)^.*{re.escape(method)}.*passed.*$", result.stdout)
    if not passed or "** TEST SUCCEEDED **" not in result.stdout:
        raise RuntimeError("Focused native BackgroundTasks test did not report passed")

print("Native BackgroundTasks verified: pending request parity and scoped cancellation")
