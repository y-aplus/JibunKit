import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("media_verification", ROOT / "Tools/verify-media.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MediaVerificationTests(unittest.TestCase):
    sources = ["final class AudioTests: XCTestCase { func testOwner() {} }",
               "final class CaptureTests: XCTestCase { func testOwner() {} }"]
    def report(self):
        return {"testNodes": [{"nodeType": "Test Suite", "children": [
            {"nodeType": "Test Case", "nodeIdentifier": cls + "/testOwner()", "result": "Passed"}
            for cls in ["AudioTests", "CaptureTests"]]}]}

    def summary(self):
        return {"result": "Passed", "failedTests": 0, "skippedTests": 0, "passedTests": 2}

    def test_structured_pass_required_for_each_class(self):
        self.assertEqual(MODULE.require_test_passes(self.report(), self.summary(), self.sources),
                         ["AudioTests.testOwner", "CaptureTests.testOwner"])
        for change in ["missing", "duplicate", "skipped", "failed", "unknown"]:
            report = self.report(); nodes = report["testNodes"][0]["children"]
            if change == "missing": nodes.pop()
            elif change == "duplicate": nodes.append(dict(nodes[0]))
            else: nodes[1]["result"] = change.title()
            with self.assertRaises(ValueError):
                MODULE.require_test_passes(report, self.summary(), self.sources)
        for key, value in [("result", "Failed"), ("failedTests", 1), ("skippedTests", 1), ("passedTests", 1)]:
            summary = self.summary(); summary[key] = value
            with self.assertRaises(ValueError):
                MODULE.require_test_passes(self.report(), summary, self.sources)

    def test_no_test_declarations_cannot_pass(self):
        for sources in [[], ["final class Empty: XCTestCase {}"]]:
            with self.assertRaises(ValueError):
                MODULE.require_test_passes(self.report(), self.summary(), sources)

    def test_built_app_must_have_usage_descriptions_and_background_audio(self):
        info = {"CFBundleIdentifier": "com.jibunkit.app", "NSCameraUsageDescription": "camera",
                "NSMicrophoneUsageDescription": "mic", "UIBackgroundModes": ["audio"]}
        MODULE.check_requirements(info)
        for key in info:
            broken = dict(info)
            del broken[key]
            with self.assertRaises(ValueError):
                MODULE.check_requirements(broken)
