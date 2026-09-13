#!/usr/bin/env python3
"""Exercise the actual incoming store across independent macOS processes."""
import json
import pathlib
import select
import subprocess
import tempfile


def main():
    subprocess.run(["swift", "build", "--product", "IncomingProcessProbe"], check=True)
    binary_dir = subprocess.check_output(["swift", "build", "--show-bin-path"], text=True).strip()
    binary = str(pathlib.Path(binary_dir) / "IncomingProcessProbe")
    with tempfile.TemporaryDirectory(prefix="incoming-processes-") as directory:
        def run(*args, check=True):
            return subprocess.run([binary, directory, *args], check=check, capture_output=True, text=True, timeout=30)

        run("prepare")
        producers = [subprocess.Popen([binary, directory, "enqueue", owner, "100"],
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for owner in ("process-a", "process-b")]
        for process in producers:
            output, error = process.communicate(timeout=30)
            assert process.returncode == 0, error
            assert len(output.splitlines()) == 100
        before_b = json.loads(run("list", "process-b").stdout)
        assert len(before_b) == 100
        assert len(json.loads(run("list", "process-a").stdout)) == 100
        run("close")
        assert run("enqueue", "process-a", "1", check=False).returncode != 0

        pin = subprocess.Popen([binary, directory, "pin"], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        removal = None
        try:
            assert select.select([pin.stdout], [], [], 30)[0], "Pin process did not reach accessor"
            assert pin.stdout.readline().startswith("pinned:")
            # B must make progress while A's accessor is deliberately blocked.
            run("enqueue", "process-b", "1")
            before_b = json.loads(run("list", "process-b").stdout)
            removal = subprocess.Popen([binary, directory, "delete"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                removal.communicate(timeout=0.5)
                raise AssertionError("Removal returned while another process held the receipt")
            except subprocess.TimeoutExpired:
                pass
            pin.communicate(input="release\n", timeout=30)
            assert pin.returncode == 0
            _, error = removal.communicate(timeout=30)
            assert removal.returncode == 0, error
        finally:
            for process in (pin, removal):
                if process is not None and process.poll() is None:
                    process.kill()
                    process.communicate()
        assert json.loads(run("list", "process-a").stdout) == []
        assert json.loads(run("list", "process-b").stdout) == before_b
        run("enqueue", "process-b", "1")
        assert len(json.loads(run("list", "process-b").stdout)) == 102
    print("passed: 200 concurrent incoming commits; cross-process pin/close/delete; B preserved and writable")


if __name__ == "__main__":
    main()
