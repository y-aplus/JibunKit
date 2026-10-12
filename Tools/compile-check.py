#!/usr/bin/env python3
"""Compile the working tree for iOS on GitHub with one command.

  python3 Tools/compile-check.py [--draft Notes [--ignore-check]]

snapshots the working tree, uncommitted and untracked files included, as a
commit on top of HEAD without changing your branch or index, pushes it to a
temporary `compile-check/...` branch of `origin`, runs the "Compile check"
workflow (.github/workflows/compile-check.yml) there, waits and prints its
report: the check findings and the compiler errors as `file:line:col`. The
temporary branch is deleted afterwards, whether the check passed or not.

Like the workflow, it proves only that the code compiles; it runs no tests and
makes no IPA. It needs Git, Python 3 and a signed-in GitHub CLI (`gh`), so it
also works on Windows and Linux.
"""
import argparse
from datetime import datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = "compile-check.yml"
BRANCH_PREFIX = "compile-check/"
REPORT_START = "=== JibunKit import report ==="
REPORT_END = "=== end of report ==="
LOG_PREFIX = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z ?")

_spec = importlib.util.spec_from_file_location("build_ipa", ROOT / "Tools/build-ipa.py")
build_ipa = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(build_ipa)
Failure, parse_repo, pick_run, run, git = (build_ipa.Failure, build_ipa.parse_repo, build_ipa.pick_run,
                                           build_ipa.run, build_ipa.git)

GH_PUSH = ["git", "-c", "credential.https://github.com.helper=",
           "-c", "credential.https://github.com.helper=!gh auth git-credential"]


def snapshot():
    """Commit the working tree on top of HEAD in a temporary index; return (commit, changed files)."""
    head = git("rev-parse", "HEAD")
    with tempfile.TemporaryDirectory() as temporary:
        env = {**os.environ, "GIT_INDEX_FILE": str(Path(temporary) / "index")}

        def indexed(*args):
            result = subprocess.run(["git", *args], cwd=ROOT, env=env, text=True, encoding="utf-8",
                                    capture_output=True)
            if result.returncode != 0:
                raise Failure(f"`git {' '.join(args)}` failed: {result.stderr.strip()}")
            return result.stdout.strip()

        indexed("read-tree", "HEAD")
        indexed("add", "--all")
        tree = indexed("write-tree")
        changed = [line for line in indexed("diff", "--cached", "--name-only", "HEAD").splitlines() if line]
    if not changed:
        return head, []
    commit = git("commit-tree", tree, "-p", head, "-m", "Compile check of the working tree")
    return commit, changed


def report_from_log(log):
    """The lines between the report markers in `gh run view --log` output, without the log prefixes."""
    lines, inside = [], False
    for raw in log.splitlines():
        line = LOG_PREFIX.sub("", raw.split("\t")[-1]).rstrip()
        if line == REPORT_START:
            lines, inside = [], True
        elif line == REPORT_END and inside:
            return "\n".join(lines)
        elif inside:
            lines.append(line)
    return None


def push(ref_spec):
    result = subprocess.run([*GH_PUSH, "push", "origin", ref_spec], cwd=ROOT, text=True, encoding="utf-8",
                            capture_output=True)
    if result.returncode != 0:
        if "`workflow` scope" in result.stderr:
            raise Failure("The snapshot changes a workflow file, which needs the `workflow` scope. Run\n"
                          "  gh auth refresh -h github.com -s workflow\nand try again.")
        raise Failure(f"git push failed: {result.stderr.strip()}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", help="OWNER/REPO to compile in (default: the `origin` remote)")
    parser.add_argument("--draft", help="Draft Feature to connect for this check only (a name under Modules/)")
    parser.add_argument("--ignore-check", action="store_true",
                        help="Connect the draft although `check` still reports findings")
    args = parser.parse_args(argv)
    if args.ignore_check and not args.draft:
        parser.error("--ignore-check needs --draft")
    if shutil.which("gh") is None:
        raise Failure("GitHub CLI `gh` is not installed: https://cli.github.com")

    repo = args.repo or parse_repo(git("remote", "get-url", "origin"))
    commit, changed = snapshot()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    branch = f"{BRANCH_PREFIX}{stamp}-{commit[:7]}"
    print(f"Compiling {'HEAD' if not changed else f'HEAD with {len(changed)} changed file(s)'} "
          f"on the temporary branch {branch} of {repo}...")
    push(f"{commit}:refs/heads/{branch}")
    run_id = None
    try:
        # GitHub and this machine may disagree slightly about the time.
        since = datetime.now(timezone.utc) - timedelta(minutes=2)
        command = ["gh", "workflow", "run", WORKFLOW, "--repo", repo, "--ref", branch]
        if args.draft:
            command += ["-f", f"draft={args.draft}", "-f", f"ignore_check={str(args.ignore_check).lower()}"]
        run(command)
        for _ in range(30):
            time.sleep(3)
            runs = json.loads(run(["gh", "run", "list", "--repo", repo, "--workflow", WORKFLOW,
                                   "--branch", branch, "--limit", "5",
                                   "--json", "databaseId,headSha,createdAt"], capture=True))
            run_id = pick_run(runs, commit, since)
            if run_id:
                break
        if not run_id:
            raise Failure(f"The workflow did not start. Check https://github.com/{repo}/actions/workflows/{WORKFLOW}")
        url = f"https://github.com/{repo}/actions/runs/{run_id}"
        print(f"Run {run_id}; this usually takes 5 to 10 minutes.\n  {url}")
        run(["gh", "run", "watch", str(run_id), "--repo", repo, "--interval", "20"], capture=True, check=False)
        conclusion = run(["gh", "run", "view", str(run_id), "--repo", repo, "--json", "conclusion",
                          "--jq", ".conclusion"], capture=True)
        passed = conclusion == "success"
        report = report_from_log(run(["gh", "run", "view", str(run_id), "--repo", repo, "--log"],
                                     capture=True, check=False) or "")
        if report is None:
            # The checks failed before the compile step wrote its report.
            failed = run(["gh", "run", "view", str(run_id), "--repo", repo, "--log-failed"],
                         capture=True, check=False) or ""
            report = "\n".join(LOG_PREFIX.sub("", line.split("\t")[-1]) for line in failed.splitlines()[-60:])
        print(f"\n{report}\n")
    except KeyboardInterrupt:
        if run_id:
            run(["gh", "run", "cancel", str(run_id), "--repo", repo], check=False)
        raise
    finally:
        push(f":refs/heads/{branch}")
        print(f"Deleted the temporary branch {branch}.")
    if not passed:
        raise Failure(f"The compile check failed ({conclusion}). Full log: gh run view {run_id} --repo {repo} --log")
    print("The compile check passed.")
    return 0


if __name__ == "__main__":
    # Show progress as it happens when the output goes to a pipe or a file.
    sys.stdout.reconfigure(line_buffering=True)
    try:
        sys.exit(main())
    except Failure as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nStopped: the run was cancelled and the temporary branch deleted.", file=sys.stderr)
        sys.exit(130)
