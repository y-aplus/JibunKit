#!/usr/bin/env python3
"""Build JibunKit.ipa from the current branch with one command.

  python3 Tools/build-ipa.py

runs the pre-build checks here, pushes the branch to `origin`, starts the
"Build IPA (quick)" workflow (.github/workflows/quick-ipa.yml) in that
repository, waits for it and prints a direct IPA link a device can open and
pass to SideStore or AltStore. Commit your changes first: the build uses the
pushed commit. It needs Git, Python 3 and a signed-in GitHub CLI (`gh`), so it
also works on Windows and Linux.

The build runs no tests. Use "Build JibunKit IPA" to test JibunKit itself.
"""
import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = "quick-ipa.yml"
ARTIFACT = "JibunKit-ad-hoc"
CHECKS = [
    ["Tools/jibunkit-feature.py", "sync", "--check"],
    ["Tools/jibunkit-feature.py", "check"],
    ["Tools/check-localization.py"],
]


class Failure(Exception):
    pass


def parse_repo(url):
    """Return OWNER/REPO for a GitHub remote URL."""
    match = re.match(r"^(?:https://(?:[^@/]+@)?github\.com/|git@github\.com:|ssh://git@github\.com/)"
                     r"([^/]+)/([^/]+?)(?:\.git)?/?$", url.strip())
    if not match:
        raise Failure(f"origin is not a GitHub repository: {url.strip()}")
    return f"{match.group(1)}/{match.group(2)}"


def pick_run(runs, sha, since):
    """Return the ID of the newest run for `sha` created at or after `since`."""
    candidates = [
        run for run in runs
        if run["headSha"] == sha
        and datetime.fromisoformat(run["createdAt"].replace("Z", "+00:00")) >= since
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda run: run["createdAt"])["databaseId"]


def run(command, capture=False, check=True):
    result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8",
                            capture_output=capture)
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip() if capture else ""
        raise Failure(f"`{' '.join(command)}` failed{': ' + detail if detail else ''}")
    return result.stdout.strip() if capture else result.returncode


def git(*args):
    return run(["git", *args], capture=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", help="OWNER/REPO to build in (default: the `origin` remote)")
    parser.add_argument("--download", action="store_true",
                        help="Download the IPA to build/ipa-RUN_ID instead of publishing a prerelease")
    args = parser.parse_args(argv)

    if shutil.which("gh") is None:
        raise Failure("GitHub CLI `gh` is not installed: https://cli.github.com")

    print("Checking Feature connections and strings...")
    for check in CHECKS:
        run([sys.executable, *check])

    changed = [line for line in git("status", "--porcelain", "--untracked-files=no").splitlines() if line]
    if changed:
        raise Failure("Commit or stash your changes first; the build uses the pushed commit:\n  "
                      + "\n  ".join(changed))
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    if branch == "HEAD":
        raise Failure("Check out a branch first; a detached HEAD cannot be pushed.")
    sha = git("rev-parse", "HEAD")
    repo = args.repo or parse_repo(git("remote", "get-url", "origin"))

    print(f"Pushing {branch} to {repo}...")
    run(["git", "push", "origin", f"HEAD:refs/heads/{branch}"])

    # GitHub and this machine may disagree slightly about the time.
    since = datetime.now(timezone.utc) - timedelta(minutes=2)
    publish = "false" if args.download else "true"
    run(["gh", "workflow", "run", WORKFLOW, "--repo", repo, "--ref", branch, "-f", f"publish={publish}"])
    run_id = None
    for _ in range(30):
        time.sleep(3)
        runs = json.loads(run(["gh", "run", "list", "--repo", repo, "--workflow", WORKFLOW, "--branch", branch,
                               "--event", "workflow_dispatch", "--limit", "10",
                               "--json", "databaseId,headSha,createdAt"], capture=True))
        run_id = pick_run(runs, sha, since)
        if run_id:
            break
    if not run_id:
        raise Failure(f"The workflow did not start. Check https://github.com/{repo}/actions/workflows/{WORKFLOW}")

    url = f"https://github.com/{repo}/actions/runs/{run_id}"
    print(f"Building {sha[:7]} in run {run_id}; this usually takes about 10 minutes.\n  {url}")
    if run(["gh", "run", "watch", str(run_id), "--repo", repo, "--exit-status", "--interval", "30"],
           check=False) != 0:
        run(["gh", "run", "view", str(run_id), "--repo", repo], check=False)
        raise Failure(f"The build failed. Compiler errors are listed above and in {url}\n"
                      f"  Full log of the failed step: gh run view {run_id} --repo {repo} --log-failed")

    if args.download:
        directory = Path("build") / f"ipa-{run_id}"
        run(["gh", "run", "download", str(run_id), "--repo", repo, "--name", ARTIFACT, "--dir", str(directory)])
        print(f"\nIPA: {ROOT / directory / 'JibunKit.ipa'}")
    else:
        print(f"\nIPA for SideStore or AltStore (open on the device):\n"
              f"  https://github.com/{repo}/releases/download/build-{run_id}/JibunKit.ipa")
        print("A private repository asks you to sign in to GitHub in the browser first.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Failure as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nStopped waiting. The build keeps running on GitHub.", file=sys.stderr)
        sys.exit(130)
