"""Run two-owner native background URLSession downloads on iOS Simulator."""
import argparse
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument("--simulator-id", required=True)
parser.add_argument("--tuist", default="tuist")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
fixture = repo / "Tests/BackgroundURLSessionNative"

with tempfile.TemporaryDirectory(prefix="jibunkit-background-urlsession-native-") as temp:
    root = Path(temp)
    (root / "Tuist").mkdir()
    project = (fixture / "Project.swift.fixture").read_text()
    project = project.replace("__JIBUNKIT_PATH__", str(repo).replace("\\", "/"))
    (root / "Project.swift").write_text(project)
    shutil.copyfile(fixture / "App.swift", root / "App.swift")
    shutil.copyfile(fixture / "UITests.swift", root / "UITests.swift")

    port_file = root / "network-port"
    server = subprocess.Popen([
        "python3", str(repo / "Tests/Fixtures/network_server.py"), str(port_file)
    ])
    try:
        for _ in range(100):
            if port_file.exists():
                break
            time.sleep(0.05)
        if not port_file.exists():
            raise RuntimeError("Loopback HTTP fixture did not publish its port")
        port = port_file.read_text(encoding="ascii").strip()
        environment = dict(
            os.environ,
            BACKGROUND_URLSESSION_BASE_URL=f"http://127.0.0.1:{port}/",
        )
        subprocess.run([args.tuist, "generate", "--no-open"], cwd=root, check=True)
        subprocess.run([
            "xcrun", "simctl", "uninstall", args.simulator_id,
            "com.jibunkit.background-urlsession-native",
        ], check=False)
        subprocess.run([
            "xcodebuild", "test",
            "-workspace", "BackgroundURLSessionNative.xcworkspace",
            "-scheme", "BackgroundURLSessionNative",
            "-destination", f"platform=iOS Simulator,id={args.simulator_id}",
            "-derivedDataPath", str(root / "DerivedData"),
            "-resultBundlePath", str(Path(os.environ["RUNNER_TEMP"]) / "BackgroundURLSessionNative.xcresult"),
            "-parallel-testing-enabled", "NO",
            "CODE_SIGNING_ALLOWED=NO",
        ], cwd=root, env=environment, check=True)
    finally:
        server.terminate()
        server.wait(timeout=10)

print("Native background URLSession verified: owner destinations and scoped cancellation")

