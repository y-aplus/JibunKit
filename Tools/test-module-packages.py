"""Run tests declared by independent Feature packages; never require new tests."""
import json
from pathlib import Path
import subprocess
import sys


def main(root: Path) -> None:
    for manifest in sorted(root.glob("*/Package.swift")):
        package = manifest.parent
        # A Feature with iOS-only tests can supply its own xcodebuild invocation.
        # This is an explicit test entry point, not automatic platform inference.
        ios_runner = package / "ci-test.sh"
        if ios_runner.is_file():
            print(f"Run Feature-owned test entry point: {ios_runner}", flush=True)
            subprocess.run(["bash", "ci-test.sh"], cwd=package, check=True)
            continue
        description = json.loads(subprocess.check_output(
            ["swift", "package", "--package-path", str(package), "dump-package"], text=True
        ))
        tests = [target["name"] for target in description["targets"] if target["type"] == "test"]
        if not tests:
            print(f"No declared Package tests: {package}", flush=True)
            continue
        print(f"Test {package}: {', '.join(tests)}", flush=True)
        subprocess.run(["swift", "test", "--package-path", str(package)], check=True)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "Modules"))
