"""The real fixture must be serving before the child runs and close afterwards."""
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "Tests/Fixtures/network_server.py"


class NetworkFixtureCommandTests(unittest.TestCase):
    def run_fixture(self, exit_code):
        with tempfile.TemporaryDirectory() as directory:
            port_file = Path(directory) / "observed-port"
            child = """
import os, pathlib, sys, urllib.request
port = os.environ['JIBUNKIT_NETWORK_TEST_PORT']
assert os.environ['TEST_RUNNER_JIBUNKIT_NETWORK_TEST_PORT'] == port
request = urllib.request.Request('http://127.0.0.1:' + port + '/echo',
                                 headers={'Cookie': 'account=fixture-child'})
with urllib.request.urlopen(request, timeout=5) as response:
    assert response.status == 200
    assert response.read() == b'account=fixture-child'
pathlib.Path(sys.argv[1]).write_text(port)
sys.exit(int(sys.argv[2]))
"""
            result = subprocess.run(
                [sys.executable, str(FIXTURE), "--run-command", sys.executable,
                 "-c", child, str(port_file), str(exit_code)],
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, exit_code, result.stdout + result.stderr)
            self.assertIn("Loopback HTTP fixture ready", result.stdout)
            port = int(port_file.read_text())
            with socket.socket() as connection:
                connection.settimeout(1)
                self.assertNotEqual(connection.connect_ex(("127.0.0.1", port)), 0)

    def test_ready_environment_and_cleanup_after_success(self):
        self.run_fixture(0)

    def test_child_failure_is_preserved_and_server_closes(self):
        self.run_fixture(7)


if __name__ == "__main__":
    unittest.main()
