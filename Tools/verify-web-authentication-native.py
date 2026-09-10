"""Run a credential-free ASWebAuthenticationSession browser handoff probe."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import threading

parser = argparse.ArgumentParser()
parser.add_argument("--simulator-id", required=True)
parser.add_argument("--tuist", default="tuist")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
fixture = repo / "Tests/WebAuthenticationNative"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/complete":
            body = b'<a href="jibunkit-auth-probe://callback?code=local">Return to App</a>'
        elif self.path == "/hold":
            body = b'<title>Hold for cancellation</title><p>Cancel this authentication session.</p>'
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *values):
        pass

server = ThreadingHTTPServer(("127.0.0.1", 8765), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with tempfile.TemporaryDirectory(prefix="jibunkit-web-auth-native-") as temp:
        root = Path(temp)
        (root / "Tuist").mkdir()
        project = (fixture / "Project.swift.fixture").read_text()
        project = project.replace("__JIBUNKIT_PATH__", str(repo).replace("\\", "/"))
        (root / "Project.swift").write_text(project)
        shutil.copyfile(fixture / "App.swift", root / "App.swift")
        shutil.copyfile(fixture / "UITests.swift", root / "UITests.swift")
        subprocess.run([args.tuist, "generate", "--no-open"], cwd=root, check=True)
        subprocess.run([
            "xcodebuild", "test", "-workspace", "WebAuthenticationNative.xcworkspace",
            "-scheme", "WebAuthenticationNative", "-destination",
            f"platform=iOS Simulator,id={args.simulator_id}", "-derivedDataPath",
            str(root / "DerivedData"), "-resultBundlePath",
            str(Path(os.environ["RUNNER_TEMP"]) / "WebAuthentication.xcresult"),
            "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO",
        ], cwd=root, check=True)
finally:
    server.shutdown()
    server.server_close()

print("Native web authentication verified: Apple baseline and JibunKit wrapper callback/cancel")
