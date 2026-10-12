import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("smoke_test", ROOT / "Tools/smoke-test.py")
smoke_test = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke_test)

APP = "/Users/runner/Library/Developer/CoreSimulator/Devices/X/data/Containers/Bundle/Application/Y/JibunKit_App.app"


class ListingTests(unittest.TestCase):
    def test_reads_ids_and_titles_and_ignores_other_output(self):
        output = ("objc[1]: some warning\r\njibunkit-mini-app\tcounter\tCounter\r\n"
                  "jibunkit-mini-app\tnotes\tMy Notes\njibunkit-mini-app\tbare\n")
        self.assertEqual(smoke_test.parse_mini_apps(output),
                         [("counter", "Counter"), ("notes", "My Notes"), ("bare", "bare")])

    def test_running_process(self):
        listing = ("PID\tStatus\tLabel\n123\t0\tUIKitApplication:com.jibunkit.app[4f2a][rb-legacy]\n"
                   "-\t0\tUIKitApplication:com.jibunkit.app.other[1][rb-legacy]\n")
        self.assertTrue(smoke_test.is_running(listing, "com.jibunkit.app"))
        self.assertFalse(smoke_test.is_running(listing, "com.jibunkit.app.other"))
        self.assertFalse(smoke_test.is_running(listing, "com.example.missing"))


class CrashTests(unittest.TestCase):
    body = {
        "exception": {"type": "EXC_BREAKPOINT", "signal": "SIGTRAP"},
        "asi": {"libswiftCore.dylib": ["Fatal error: Unexpectedly found nil while unwrapping"]},
        "faultingThread": 1,
        "usedImages": [{"name": "libswiftCore.dylib", "path": "/usr/lib/swift/libswiftCore.dylib"},
                       {"name": "JibunKit_App.debug.dylib", "path": APP + "/JibunKit_App.debug.dylib"}],
        "threads": [{"frames": []}, {"frames": [
            {"imageIndex": 0, "symbol": "_assertionFailure"},
            {"imageIndex": 1, "symbol": "NotesRootView.body.getter", "sourceFile": "NotesRootView.swift",
             "sourceLine": 12},
            {"imageIndex": 1, "symbol": "closure #1 in NotesStore.load()"},
        ]}],
    }

    def test_reason_and_own_frames(self):
        self.assertEqual(smoke_test.describe_crash(self.body), [
            "EXC_BREAKPOINT / SIGTRAP",
            "Fatal error: Unexpectedly found nil while unwrapping",
            "at NotesRootView.body.getter (NotesRootView.swift:12) in JibunKit_App.debug.dylib",
            "at closure #1 in NotesStore.load() in JibunKit_App.debug.dylib",
        ])

    def test_system_frames_when_the_app_has_none(self):
        body = {"exception": {"type": "EXC_CRASH", "signal": "SIGABRT"},
                "usedImages": [{"name": "libsystem_kernel.dylib", "path": "/usr/lib/system/libsystem_kernel.dylib"}],
                "threads": [{"frames": [{"imageIndex": 0, "symbol": "__pthread_kill"}]}]}
        self.assertEqual(smoke_test.describe_crash(body),
                         ["EXC_CRASH / SIGABRT", "at __pthread_kill in libsystem_kernel.dylib"])

    def test_parses_an_ips_file(self):
        text = json.dumps({"bundleID": "com.jibunkit.app", "bug_type": "309"}) + "\n" + json.dumps(self.body, indent=2)
        header, body = smoke_test.parse_crash_report(text)
        self.assertEqual(header["bundleID"], "com.jibunkit.app")
        self.assertEqual(body["faultingThread"], 1)
        self.assertIsNone(smoke_test.parse_crash_report("not json\n{}"))


class ReportTests(unittest.TestCase):
    def test_lists_results_and_screenshot_links(self):
        report = smoke_test.format_report(
            "iPhone 16e, iOS-26-0",
            [("home", "Mini app list", "OK", [], "home.jpg"),
             ("notes", "Notes", "CRASHED", ["EXC_BREAKPOINT / SIGTRAP"], None)],
            None, "https://github.com/o/r/releases/download/launch-1")
        self.assertEqual(report.splitlines(), [
            "Opened 2 mini app(s) in the iOS Simulator (iPhone 16e, iOS-26-0), Debug build:",
            "OK       Mini app list (home)",
            "         screenshot: https://github.com/o/r/releases/download/launch-1/home.jpg",
            "CRASHED  Notes (notes)",
            "         EXC_BREAKPOINT / SIGTRAP",
        ])

    def test_launch_crash(self):
        report = smoke_test.format_report("iPhone", [], ["Mini-app IDs must be unique."], None)
        self.assertEqual(report.splitlines(), ["JibunKit stopped before it listed its mini apps:",
                                               "  Mini-app IDs must be unique."])


if __name__ == "__main__":
    unittest.main()
