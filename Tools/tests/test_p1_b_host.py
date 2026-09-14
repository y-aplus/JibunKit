import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("p1_b_host", ROOT / "Tools/prepare-p1-b-host.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class P1BHostTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.host = Path(self.temp.name)
        for name in ["Project.swift", "Package.swift", "Sources/JibunKit/MiniAppRegistry.swift"]:
            target = self.host / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        fixtures = self.host / "Tests/TemplateIntegration"
        fixtures.mkdir(parents=True)
        for name in MODULE.PROBES.values():
            for suffix in ["Probe", "UITests"]:
                (fixtures / f"{name}{suffix}.swift").write_text(f"// source {name}{suffix}\n", encoding="utf-8")

    def snapshot(self):
        return {p.relative_to(self.host).as_posix(): p.read_bytes()
                for p in self.host.rglob("*") if p.is_file()}

    def testAllPairsPreserveNormalTargetsAndCopyExactSources(self):
        original = self.snapshot()
        MODULE.prepare(self.host, ["notifications", "http", "web"])
        registry = (self.host / "Sources/JibunKit/MiniAppRegistry.swift").read_text(encoding="utf-8")
        for name in MODULE.PROBES.values():
            for owner in ["A", "B"]:
                self.assertEqual(registry.count(f"{name}Probe.owner{owner}Definition,"), 1)
            for suffix, directory in [("Probe", "Sources/JibunKit"), ("UITests", "UITests")]:
                self.assertEqual((self.host / directory / f"{name}{suffix}.swift").read_bytes(),
                                 (self.host / "Tests/TemplateIntegration" / f"{name}{suffix}.swift").read_bytes())
        for name in ["Project.swift", "Package.swift"]:
            self.assertEqual((self.host / name).read_bytes(), original[name])
        self.assertIn("CounterMiniApp.definition", registry)
        self.assertIn("ReminderMiniApp.definition", registry)

    def testMissingLaterPairCannotPartiallyConnectEarlierLane(self):
        (self.host / "Tests/TemplateIntegration/P1WebUITests.swift").unlink()
        before = self.snapshot()
        with self.assertRaises(FileNotFoundError):
            MODULE.prepare(self.host, ["notifications", "web"])
        self.assertEqual(self.snapshot(), before)

    def testRepeatedPreparationFailsWithoutChangingAnything(self):
        MODULE.prepare(self.host, ["notifications"])
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "already connected"):
            MODULE.prepare(self.host, ["notifications"])
        self.assertEqual(self.snapshot(), before)

    def testUnselectedPairsNotRequiredAndLaterLaneCanCompose(self):
        (self.host / "Tests/TemplateIntegration/P1HTTPUITests.swift").unlink()
        MODULE.prepare(self.host, ["notifications"])
        MODULE.prepare(self.host, ["web"])
        registry = (self.host / "Sources/JibunKit/MiniAppRegistry.swift").read_text(encoding="utf-8")
        self.assertIn("P1NotificationsProbe.ownerADefinition", registry)
        self.assertIn("P1WebProbe.ownerBDefinition", registry)
        self.assertNotIn("P1HTTPProbe", registry)

    def testUnknownLayoutFailsBeforeCopies(self):
        project = self.host / "Project.swift"
        project.write_text("changed layout", encoding="utf-8")
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "source glob"):
            MODULE.prepare(self.host, ["notifications"])
        self.assertEqual(self.snapshot(), before)

    def testExistingSourceIsPreserved(self):
        target = self.host / "UITests/P1NotificationsUITests.swift"
        target.parent.mkdir()
        target.write_text("local work", encoding="utf-8")
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "overwrite"):
            MODULE.prepare(self.host, ["notifications"])
        self.assertEqual(self.snapshot(), before)
