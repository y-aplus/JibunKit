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
    log = ("Test Case '-[Media.AudioTests testOwner]' passed (0.01 seconds).\n"
           "Test Case '-[Media.CaptureTests testOwner]' passed (0.01 seconds).\n"
           "** TEST SUCCEEDED **\n")

    def test_real_pass_required_for_each_class_not_just_same_method_name(self):
        self.assertEqual(MODULE.require_test_passes(self.log, self.sources),
                         ["AudioTests.testOwner", "CaptureTests.testOwner"])
        for log in [self.log.replace("CaptureTests", "WrongTests"), self.log + self.log,
                    self.log.replace("passed", "skipped"), self.log.replace("** TEST SUCCEEDED **", "")]:
            with self.assertRaises(ValueError):
                MODULE.require_test_passes(log, self.sources)

    def test_no_test_declarations_cannot_pass(self):
        with self.assertRaises(ValueError):
            MODULE.require_test_passes(self.log, [])
        with self.assertRaises(ValueError):
            MODULE.require_test_passes(self.log, ["final class Empty: XCTestCase {}"])

    def test_built_app_must_have_usage_descriptions_and_background_audio(self):
        info = {"CFBundleIdentifier": "com.jibunkit.app", "NSCameraUsageDescription": "camera",
                "NSMicrophoneUsageDescription": "mic", "UIBackgroundModes": ["audio"]}
        MODULE.check_requirements(info)
        for key in info:
            broken = dict(info)
            del broken[key]
            with self.assertRaises(ValueError):
                MODULE.check_requirements(broken)
