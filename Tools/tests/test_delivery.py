import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import subprocess
import sys

SPEC = importlib.util.spec_from_file_location("delivery", Path(__file__).resolve().parents[1] / "check-delivery.py")
delivery = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(delivery)
SHA = "a" * 40


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.plan = json.loads((delivery.ROOT / "docs/delivery/plan.json").read_text(encoding="utf-8"))

    def report(self, wave="P0-A", with_device=False):
        result = delivery.template(self.plan, wave, SHA)
        result["contract"] = {k: "reviewed contract reference" for k in result["contract"]}
        result["contract"]["baseline"] = SHA
        result["dependencies"] = {d: "prior reviewed evidence" for d in result["dependencies"]}
        selected = next(w for w in self.plan["waves"] if w["id"] == wave)["checks"]
        for u in self.plan["units"]:
            if u["id"] not in selected:
                continue
            for c in u["criteria"]:
                if c["kinds"] == ["device"] and not with_device:
                    continue
                result["evidence"].append({"criterion": c["id"], "kind": c["kinds"][0],
                    "source": SHA, "result": "passed", "reference": "test fixture reference",
                    "observation": "expected owner data retained", "review": "reviewed"})
        if with_device:
            result["deferred_device"] = {}
        result["runs"] = [{"id": "run-1/attempt-1", "url": "test-fixture://run-1", "source": SHA, "conclusion": "success"}]
        return result

    def test_real_plan_and_incomplete_template(self):
        delivery.validate_plan(self.plan)
        with self.assertRaisesRegex(ValueError, "contract/review"):
            delivery.validate_report(self.plan, delivery.template(self.plan, "P0-A", SHA), "preflight")

    def test_ci_allows_scheduled_device_without_claiming_release(self):
        report = self.report()
        delivery.validate_report(self.plan, report, "ci")
        report["deferred_device"] = {}
        with self.assertRaisesRegex(ValueError, "missing passed evidence"):
            delivery.validate_report(self.plan, report, "ci")

    def test_preflight_schedules_checks_but_ci_requires_results(self):
        report = self.report()
        e = report["evidence"].pop()
        report["jobs"] = [{"id": "local", "kind": e["kind"], "criteria": [e["criterion"]],
                           "command": "review local case", "expected_minutes": 10, "timeout_minutes": 20}]
        delivery.validate_report(self.plan, report, "preflight")
        with self.assertRaisesRegex(ValueError, "missing passed evidence"):
            delivery.validate_report(self.plan, report, "ci")

    def test_evidence_type_and_duplicate_and_unknown(self):
        report = self.report(with_device=True)
        device = next(e for e in report["evidence"] if e["kind"] == "device")
        device["kind"] = "unit"
        with self.assertRaisesRegex(ValueError, "wrong evidence kind"):
            delivery.validate_report(self.plan, report, "ci")
        report = self.report()
        report["evidence"].append(copy.deepcopy(report["evidence"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate evidence"):
            delivery.validate_report(self.plan, report, "ci")
        report["evidence"][-1]["criterion"] = "P9-1.fake"
        with self.assertRaisesRegex(ValueError, "unknown evidence"):
            delivery.validate_report(self.plan, report, "ci")

    def test_old_source_requires_explicit_reviewed_reuse(self):
        report = self.report()
        report["evidence"][0]["source"] = "b" * 40
        with self.assertRaisesRegex(ValueError, "reviewed reuse"):
            delivery.validate_report(self.plan, report, "ci")
        report["evidence"][0]["reuse_reason"] = "Reviewed diff; docs only, runtime and dependencies unchanged"
        delivery.validate_report(self.plan, report, "ci")

    def test_failed_evidence_is_not_success(self):
        report = self.report()
        report["evidence"][0]["result"] = "failed"
        with self.assertRaisesRegex(ValueError, "not passed"):
            delivery.validate_report(self.plan, report, "ci")

    def test_ci_budget_and_long_jobs(self):
        report = self.report()
        report["planned_ci_runs"] = 3
        with self.assertRaisesRegex(ValueError, "budget exceeded"):
            delivery.validate_report(self.plan, report, "ci")
        report["budget_exception"] = "One additional independent regression shard needed"
        delivery.validate_report(self.plan, report, "ci")
        report["jobs"] = [{"id": "oversized", "kind": "unit", "criteria": ["P0-1.lifetime"],
                           "command": "tests", "expected_minutes": 60, "timeout_minutes": 90}]
        with self.assertRaisesRegex(ValueError, "split long jobs"):
            delivery.validate_report(self.plan, report, "preflight")

    def test_bad_graph_missing_milestone_and_duplicate_units(self):
        invalid = copy.deepcopy(self.plan)
        invalid["waves"][0]["requires"] = ["P0-C"]
        with self.assertRaisesRegex(ValueError, "cycle"):
            delivery.validate_plan(invalid)
        invalid = copy.deepcopy(self.plan)
        invalid["milestones"]["0.8.0"].pop()
        with self.assertRaisesRegex(ValueError, "milestone units"):
            delivery.validate_plan(invalid)
        invalid = copy.deepcopy(self.plan)
        invalid["units"].append(invalid["units"][0])
        with self.assertRaisesRegex(ValueError, "duplicate unit"):
            delivery.validate_plan(invalid)

    def test_release_requires_complete_units_and_v1_decision(self):
        report = self.report("P0-C", with_device=True)
        with self.assertRaisesRegex(ValueError, "still partial"):
            delivery.validate_report(self.plan, report, "release", version="0.7.0")
        with self.assertRaisesRegex(ValueError, "boundary not decided"):
            delivery.validate_report(self.plan, report, "release", version="1.0.0")

    def test_p1_release_requires_p0_and_missing_dependency(self):
        report = self.report("P1-B", with_device=True)
        for unit in self.plan["units"]:
            if unit["priority"] == "P1":
                unit["state"] = "complete"
        with self.assertRaisesRegex(ValueError, "still partial"):
            delivery.validate_report(self.plan, report, "release", version="0.8.0")
        report["dependencies"] = {}
        with self.assertRaisesRegex(ValueError, "missing dependency"):
            delivery.validate_report(self.plan, report, "ci")

    def test_cli_does_not_clobber_evidence_or_create_invalid_template(self):
        command = [sys.executable, str(delivery.ROOT / "Tools/check-delivery.py")]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "report.json"
            result = subprocess.run(command + ["--template", "P0-A", "--source", "bad", "--output", str(path)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(path.exists())
            result = subprocess.run(command + ["--template", "P0-A", "--source", SHA, "--output", str(path)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            before = path.read_bytes()
            result = subprocess.run(command + ["--template", "P0-A", "--source", "b" * 40, "--output", str(path)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(path.read_bytes(), before)
            result = subprocess.run(command + ["--report", str(path), "--release", "0.7.0"], capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_release_docs_missing_stale_and_new_current_guide(self):
        report = self.report("P0-C", with_device=True)
        for unit in self.plan["units"]:
            if unit["priority"] == "P0":
                unit["state"] = "complete"
        report["release"] = {k: "reviewed evidence reference" for k in ("candidate_ipa", "normal_regression",
                             "generated_host", "metadata", "compatibility", "physical_review")}
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for path in delivery.current_docs(root, "0.7.0"):
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("current prose", encoding="utf-8")
                report["documents"].append({"path": path, "outcome": "reviewed-unchanged", "reason": "still accurate",
                    "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
            delivery.validate_report(self.plan, report, "release", root, "0.7.0")
            (root / "README.md").write_text("changed", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "stale document"):
                delivery.validate_report(self.plan, report, "release", root, "0.7.0")
            (root / "README.md").write_text("current prose", encoding="utf-8")
            (root / "docs/guides").mkdir()
            (root / "docs/guides/new.md").write_text("new guide", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "missing document review"):
                delivery.validate_report(self.plan, report, "release", root, "0.7.0")


if __name__ == "__main__":
    unittest.main()
