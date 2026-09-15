#!/usr/bin/env python3
"""Verify shared-state races using real independent macOS processes, not mocks."""
import json
from pathlib import Path
import select
import subprocess
import tempfile


def main():
    subprocess.run(["swift", "build", "--product", "SharedStateProcessProbe"], check=True)
    binary_dir = subprocess.check_output(["swift", "build", "--show-bin-path"], text=True).strip()
    binary = str(Path(binary_dir) / "SharedStateProcessProbe")
    with tempfile.TemporaryDirectory(prefix="shared-state-processes-") as directory:
        def command(*args):
            return [binary, directory, *args]

        def run(*args, check=True):
            return subprocess.run(command(*args), capture_output=True, text=True, timeout=30, check=check)

        def read(owner):
            return json.loads(run("read", owner).stdout)

        def stop(process):
            if process is not None and process.poll() is None:
                process.kill()
                process.communicate()

        for owner in ("shared-a", "shared-b"):
            run("prepare", owner)
        writers = []
        try:
            for owner in ("shared-a", "shared-a", "shared-b"):
                writers.append(subprocess.Popen(command("increment", owner, "100"),
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
            for writer in writers:
                _, error = writer.communicate(timeout=30)
                assert writer.returncode == 0, error
        finally:
            for writer in writers:
                stop(writer)
        assert read("shared-a")["value"] == 200, "cross-process read-modify-write lost updates"
        assert read("shared-b")["value"] == 100
        old_generation = read("shared-a")["generation"]

        # A management close must wait for an admitted write; B stays usable.
        pin = subprocess.Popen(command("pin", "shared-a"), stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        closing = None
        try:
            assert select.select([pin.stdout], [], [], 30)[0], "writer did not enter accessor"
            assert pin.stdout.readline().strip() == "pinned"
            run("increment", "shared-b", "1")
            closing = subprocess.Popen(command("close", "shared-a"), stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, text=True)
            assert select.select([closing.stdout], [], [], 30)[0], "management process did not start"
            assert closing.stdout.readline().strip() == "closing"
            try:
                closing.communicate(timeout=0.5)
                raise AssertionError("management closed before the other process finished writing")
            except subprocess.TimeoutExpired:
                pass
            _, error = pin.communicate(input="release\n", timeout=30)
            assert pin.returncode == 0, error
            _, error = closing.communicate(timeout=30)
            assert closing.returncode == 0, error
        finally:
            stop(pin)
            stop(closing)
        assert run("increment", "shared-a", "1", check=False).returncode != 0
        run("enable", "shared-a")
        assert read("shared-a")["value"] == 201

        # A process dying inside the accessor publishes no partial value and
        # releases the OS coordination. A fresh process can continue writing.
        interrupted = subprocess.Popen(command("pin", "shared-a"), stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            assert select.select([interrupted.stdout], [], [], 30)[0]
            assert interrupted.stdout.readline().strip() == "pinned"
        finally:
            stop(interrupted)
        assert read("shared-a")["value"] == 201
        run("increment", "shared-a", "1")
        assert read("shared-a")["value"] == 202
        run("close", "shared-a")
        run("remove", "shared-a")
        run("prepare", "shared-a")
        assert run("enable", "shared-a", check=False).returncode != 0, "initialization resurrected a deletion"
        run("replace", "shared-a", "1")
        run("enable", "shared-a")
        assert run("old", "shared-a", old_generation, check=False).returncode != 0
        assert read("shared-a")["value"] == 1
        assert read("shared-b")["value"] == 101
    print("passed: 300 process updates; close/write ordering; interrupted writer; tombstone/generation; B retained")


if __name__ == "__main__":
    main()
