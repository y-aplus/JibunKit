#!/usr/bin/env python3
"""Local preflight/evidence/document gate. Does not execute CI or judge evidence truth."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
KINDS = {"unit", "simulator", "device", "inspection"}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def unique(items, label):
    require(len(items) == len(set(items)), f"duplicate {label}")


def source(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}", value)


def validate_plan(plan):
    require(plan["schema"] == 1, "unsupported plan schema")
    units = {u["id"]: u for u in plan["units"]}
    waves = {w["id"]: w for w in plan["waves"]}
    unique([u["id"] for u in plan["units"]], "unit")
    unique([w["id"] for w in plan["waves"]], "wave")
    require(set(units) == {f"{p}-{i}" for p in ("P0", "P1") for i in range(1, 7)},
            "Issue #5 requires all six P0 and all six P1 units")
    criteria = []
    for uid, unit in units.items():
        require(unit["priority"] in {"P0", "P1"}, f"{uid}: invalid priority")
        require(uid.startswith(unit["priority"] + "-"), f"{uid}: priority differs from Issue #5")
        require(unit["state"] in {"partial", "complete"}, f"{uid}: invalid state")
        milestone = "0.7.0" if unit["priority"] == "P0" else "0.8.0"
        require(unit["milestone"] == milestone, f"{uid}: incorrect milestone")
        require(unit["parents"] and all(re.fullmatch(r"D(0[1-9]|[12][0-9]|3[0-2])", d)
                for d in unit["parents"]), f"{uid}: invalid parent")
        require(unit["criteria"], f"{uid}: no acceptance criteria")
        for criterion in unit["criteria"]:
            require(criterion["id"].startswith(uid + "."), f"{uid}: foreign criterion")
            require(nonempty(criterion["description"]), f"{uid}: empty criterion")
            require(criterion["kinds"] and set(criterion["kinds"]) <= KINDS,
                    f"{uid}: invalid evidence kinds")
            criteria.append(criterion["id"])
    unique(criteria, "criterion")
    require(set(plan["milestones"]) == {"0.7.0", "0.8.0"}, "unexpected milestones")
    for version, members in plan["milestones"].items():
        unique(members, "milestone member")
        expected = {uid for uid, u in units.items() if version == "0.8.0" or u["priority"] == "P0"}
        require(set(members) == expected, f"{version}: missing or extra milestone units")
    assigned = []
    for wid, wave in waves.items():
        require(wave["units"] and set(wave["units"]) <= set(wave["checks"]) <= units.keys(),
                f"{wid}: invalid unit/check scope")
        unique(wave["checks"], f"{wid} check")
        unique(wave["requires"], f"{wid} dependency")
        require(set(wave["requires"]) <= waves.keys(), f"{wid}: unknown dependency")
        require(type(wave["ci_budget"]) is int and wave["ci_budget"] > 0, f"{wid}: invalid budget")
        assigned.extend(wave["units"])
    unique(assigned, "wave assignment")
    require(set(assigned) == units.keys(), "unassigned unit")
    def visit(wid, stack):
        require(wid not in stack, "wave dependency cycle")
        for dep in waves[wid]["requires"]:
            visit(dep, stack | {wid})
    for wid in waves:
        visit(wid, set())
    return units, waves


def current_docs(root, version):
    """Dynamic inventory: current prose, not archived research or historical release notes."""
    fixed = {"README.md", "CHANGELOG.md", "CONTRIBUTING.md", "SECURITY.md",
             "THIRD_PARTY_NOTICES.md", "docs/superpowers/plans/2026-09-08-jibunkit-1.0.md",
             f"release-notes-{version}.md"}
    for pattern in ("docs/*.md", "docs/guides/**/*.md", "docs/delivery/**/*.md", "Modules/**/README.md"):
        fixed.update(p.relative_to(root).as_posix() for p in root.glob(pattern))
    return sorted(fixed)


def validate_docs(records, root, version):
    unique([r["path"] for r in records], "document review")
    by_path = {r["path"]: r for r in records}
    for path in current_docs(root, version):
        require(path in by_path, f"missing document review: {path}")
        record = by_path[path]
        file = root / path
        require(file.is_file(), f"missing current document: {path}")
        require(record["outcome"] in {"updated", "reviewed-unchanged"} and nonempty(record["reason"]),
                f"incomplete document review: {path}")
        require(record["sha256"] == hashlib.sha256(file.read_bytes()).hexdigest(),
                f"stale document review: {path}")


def validate_report(plan, report, stage, root=ROOT, version=None):
    units, waves = validate_plan(plan)
    require(report["schema"] == 1 and source(report["source"]), "invalid report source/schema")
    wid = report["wave"]
    require(wid in waves, "unknown wave")
    wave = waves[wid]
    if stage == "release":
        require(version in plan["milestones"], "release boundary not decided (including v1.0)")
        members = plan["milestones"][version]
        require(set(members) <= set(wave["checks"]), "wave does not cover release")
        require(all(units[u]["state"] == "complete" for u in members), "release units still partial")
    else:
        members = wave["checks"]
    criteria = {c["id"]: c for u in members for c in units[u]["criteria"]}
    contract = report["contract"]
    require(all(nonempty(contract[k]) for k in ("baseline", "interfaces", "ownership", "failure_cases",
            "normal_entrypoints", "invalidation", "review")), "contract/review not ready")
    require(source(contract["baseline"]), "baseline must be a full commit")
    for dep in wave["requires"]:
        require(nonempty(report["dependencies"].get(dep)), f"missing dependency evidence: {dep}")
    jobs = report["jobs"]
    unique([j["id"] for j in jobs], "job")
    scheduled = set()
    for job in jobs:
        require(job["kind"] in KINDS - {"device"}, "invalid CI/local job kind")
        require(nonempty(job["command"]) and job["criteria"], "empty job command/scope")
        require(0 < job["expected_minutes"] <= 30 and job["expected_minutes"] <= job["timeout_minutes"] <= 45,
                "split long jobs: expected <=30, timeout <=45 minutes")
        for cid in job["criteria"]:
            require(cid in criteria and job["kind"] in criteria[cid]["kinds"], f"invalid job coverage: {cid}")
            scheduled.add(cid)
    require(type(report["planned_ci_runs"]) is int and report["planned_ci_runs"] > 0, "missing CI run plan")
    runs = report["runs"]
    unique([r["id"] for r in runs], "run/attempt")
    if max(report["planned_ci_runs"], len(runs)) > wave["ci_budget"]:
        require(nonempty(report["budget_exception"]), "CI budget exceeded without explanation")
    for run in runs:
        require(nonempty(run["url"]) and source(run["source"]) and nonempty(run["conclusion"]), "incomplete run record")
    evidence = report["evidence"]
    unique([e["criterion"] for e in evidence], "evidence criterion")
    proven = set()
    for item in evidence:
        cid = item["criterion"]
        require(cid in criteria, f"unknown evidence criterion: {cid}")
        require(item["kind"] in criteria[cid]["kinds"], f"wrong evidence kind: {cid}")
        require(item["result"] == "passed" and source(item["source"]), f"not passed: {cid}")
        require(all(nonempty(item[k]) for k in ("reference", "observation", "review")), f"empty evidence: {cid}")
        if item["source"] != report["source"]:
            require(nonempty(item.get("reuse_reason")), f"different source requires reviewed reuse: {cid}")
        proven.add(cid)
    deferred = report["deferred_device"]
    for cid, target in deferred.items():
        require(cid in criteria and set(criteria[cid]["kinds"]) == {"device"}, f"invalid device deferral: {cid}")
        uid = cid.split(".")[0]
        require(target == units[uid]["milestone"], f"wrong device checkpoint: {cid}")
    for cid, criterion in criteria.items():
        if cid in proven:
            continue
        device_only = set(criterion["kinds"]) == {"device"}
        if stage != "release" and device_only and cid in deferred:
            continue
        require(stage == "preflight" and not device_only and cid in scheduled,
                f"missing {'planned check' if stage == 'preflight' else 'passed evidence'}: {cid}")
    if stage != "preflight":
        require(runs, "no CI runs recorded")
    if stage == "release":
        require(not deferred, "release cannot defer device checks")
        require(all(nonempty(report["release"][k]) for k in ("candidate_ipa", "normal_regression",
                "generated_host", "metadata", "compatibility", "physical_review")), "release evidence missing")
        validate_docs(report["documents"], root, version)
    return f"{wid}: {stage} structure/coverage passed; evidence truth requires human review"


def template(plan, wid, sha):
    units, waves = validate_plan(plan)
    require(wid in waves and source(sha), "template needs known wave and full source commit")
    wave = waves[wid]
    return {"schema": 1, "wave": wid, "source": sha,
            "contract": {k: "" for k in ("baseline", "interfaces", "ownership", "failure_cases",
                         "normal_entrypoints", "invalidation", "review")},
            "dependencies": {d: "" for d in wave["requires"]},
            "planned_ci_runs": wave["ci_budget"], "budget_exception": "", "jobs": [], "runs": [],
            "evidence": [], "deferred_device": {c["id"]: units[u]["milestone"]
                for u in wave["checks"] for c in units[u]["criteria"] if set(c["kinds"]) == {"device"}},
            "documents": [], "release": {},
            "metrics": {"review_rounds": 0, "parent_messages": 0, "ci_job_minutes": 0},
            "acceptance": {c["id"]: c["description"] for u in wave["checks"] for c in units[u]["criteria"]}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, default=ROOT / "docs/delivery/plan.json")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--stage", choices=("preflight", "ci", "release"), default="preflight")
    parser.add_argument("--release", dest="version")
    parser.add_argument("--template", metavar="WAVE")
    parser.add_argument("--source")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--list-docs", metavar="VERSION")
    args = parser.parse_args()
    try:
        plan = json.loads(args.plan.read_text(encoding="utf-8-sig"))
        validate_plan(plan)
        require(args.version is None or (args.report is not None and args.stage == "release"),
                "--release requires --report and --stage release")
        if args.list_docs:
            print("\n".join(current_docs(ROOT, args.list_docs)))
        elif args.template:
            require(args.output is not None, "template requires --output")
            draft = template(plan, args.template, args.source)
            # Exclusive creation protects existing evidence from accidental replacement.
            with args.output.open("x", encoding="utf-8", newline="\n") as output:
                json.dump(draft, output, ensure_ascii=False, indent=2)
                output.write("\n")
            print(f"Created incomplete template: {args.output}")
        elif args.report:
            report = json.loads(args.report.read_text(encoding="utf-8-sig"))
            print(validate_report(plan, report, args.stage, version=args.version))
        else:
            require(args.stage == "preflight" and args.version is None, "stage/release requires --report")
            print(f"Plan valid: {len(plan['units'])} units, {len(plan['waves'])} CI boundaries")
    except (ValueError, KeyError, TypeError, OSError) as error:
        print(f"Delivery gate failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
