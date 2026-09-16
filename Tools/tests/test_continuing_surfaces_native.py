import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("continuing_native", ROOT / "Tools/verify-continuing-surfaces.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ContinuingNativeEvidenceTests(unittest.TestCase):
    def test_owner_metadata_rejects_missing_or_foreign_feature(self):
        modules = ["ContinuingFeatureA", "ContinuingFeatureB"]
        one = {"actions": {"advance": {"fullyQualifiedTypeName": "ContinuingFeatureA.Advance"}}}
        MODULE.check_owner_metadata(one, modules, modules[:1])
        with self.assertRaises(ValueError):
            MODULE.check_owner_metadata(one, modules, modules)
        with self.assertRaises(ValueError):
            MODULE.check_owner_metadata(one, modules, modules[1:])
        with self.assertRaises(ValueError):
            MODULE.check_owner_metadata({"actions": []}, modules, modules[:1])

    def test_skipped_missing_duplicate_or_failed_xctest_is_not_success(self):
        source = "func testOne() throws {}\nfunc testTwo() async throws {}"
        passed = "Test Case '-[Probe testOne]' passed (0.1 seconds).\nTest Case '-[Probe testTwo]' passed (0.2 seconds).\n** TEST SUCCEEDED **"
        self.assertEqual(MODULE.require_test_passes(passed, source), ["testOne", "testTwo"])
        for log in [passed.replace("testTwo]' passed", "testTwo]' skipped"),
                    passed.replace("** TEST SUCCEEDED **", "** TEST FAILED **"),
                    passed + "\nTest Case '-[Probe testOne]' passed (0.1 seconds)."]:
            with self.subTest(log=log), self.assertRaises(ValueError):
                MODULE.require_test_passes(log, source)
        with self.assertRaises(ValueError):
            MODULE.require_test_passes(passed, "// no test declarations")
