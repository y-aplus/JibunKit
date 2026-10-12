import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("compile_check", ROOT / "Tools/compile-check.py")
compile_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compile_check)


class ReportFromLogTests(unittest.TestCase):
    def test_reads_the_lines_between_the_markers(self):
        log = "\n".join([
            "build\tGenerate and compile\t2026-10-12T10:00:00.1234567Z ##[group]Run set -uo pipefail",
            'build\tGenerate and compile\t2026-10-12T10:00:00.1234567Z echo "=== JibunKit import report ==="',
            "build\tGenerate and compile\t2026-10-12T10:05:00.1234567Z === JibunKit import report ===",
            "build\tGenerate and compile\t2026-10-12T10:05:00.1234567Z Compile errors (1):",
            "build\tGenerate and compile\t2026-10-12T10:05:00.1234567Z Modules/Notes/Sources/A.swift:3:5: error: x",
            "build\tGenerate and compile\t2026-10-12T10:05:00.1234567Z ",
            "build\tGenerate and compile\t2026-10-12T10:05:00.1234567Z === end of report ===",
        ])
        self.assertEqual(compile_check.report_from_log(log),
                         "Compile errors (1):\nModules/Notes/Sources/A.swift:3:5: error: x\n")

    def test_none_without_a_report(self):
        log = "build\tCheck\t2026-10-12T10:00:00.1Z error: Modules/Notes is not connected"
        self.assertIsNone(compile_check.report_from_log(log))
        self.assertIsNone(compile_check.report_from_log(
            "build\tCheck\t2026-10-12T10:00:00.1Z === JibunKit import report ===\nunfinished"))


if __name__ == "__main__":
    unittest.main()
