import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
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
        (fixtures / "P1UIVisibility.swift").write_text("// shared visibility helper\n", encoding="utf-8")
        (fixtures / "P1DeviceHTTPFixture.swift").write_text("// loopback fixture\n", encoding="utf-8")
        for name in MODULE.PROBES.values():
            for suffix in ["Probe", "UITests"]:
                (fixtures / f"{name}{suffix}.swift").write_text(f"// source {name}{suffix}\n", encoding="utf-8")

    def snapshot(self):
        return {p.relative_to(self.host).as_posix(): p.read_bytes()
                for p in self.host.rglob("*") if p.is_file()}

    def testDeviceCandidateComposesIntentsWidgetsAndAllBProbes(self):
        for relative in ["Sources/JibunKit/JibunKitApp.swift", "Sources/JibunKitWidget/CounterWidget.swift"]:
            target = self.host / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        for name in ["P1IntentsProbe.swift", "P1IntentsUITests.swift", "P1WidgetsProbe.swift", "P1WidgetsUITests.swift"]:
            shutil.copyfile(ROOT / "Tests/TemplateIntegration" / name, self.host / "Tests/TemplateIntegration" / name)
        support = self.host / "Tests/PackageWidgets/WidgetGallerySupport.swift"
        support.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "Tests/PackageWidgets/WidgetGallerySupport.swift", support)
        shutil.copyfile(ROOT / "Tests/TemplateIntegration/P1WidgetGalleryUITests.swift", self.host / "Tests/TemplateIntegration/P1WidgetGalleryUITests.swift")
        for lane in ["intents", "widgets"]:
            spec = importlib.util.spec_from_file_location(lane, ROOT / f"Tools/prepare-p1-{lane}-host.py")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            module.prepare(self.host)
        MODULE.prepare(self.host, ["notifications", "http", "web"])
        project = (self.host / "Project.swift").read_text(encoding="utf-8")
        registry = (self.host / "Sources/JibunKit/MiniAppRegistry.swift").read_text(encoding="utf-8")
        self.assertIn('product: "IntentFeatureA"', project)
        self.assertEqual(project.count('product: "P1WidgetFeatureB"'), 2)
        for declaration in ["P1IntentsProbe.definitionA", "P1WidgetsProbe.definitions[1]", "P1HTTPProbe.ownerADefinition", "P1WebProbe.ownerBDefinition", "P1NotificationsProbe.ownerADefinition"]:
            self.assertEqual(registry.count(declaration + ","), 1)

    def testAllPairsPreserveNormalTargetsAndCopyExactSources(self):
        original = self.snapshot()
        subprocess.run([sys.executable, str(ROOT / "Tools/prepare-p1-b-host.py"),
                        "--host", str(self.host), "--all-lanes"], check=True)
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
        self.assertEqual((self.host / "UITests/P1UIVisibility.swift").read_bytes(),
                         (self.host / "Tests/TemplateIntegration/P1UIVisibility.swift").read_bytes())

    def testMissingHelperCannotPartiallyConnectLane(self):
        (self.host / "Tests/TemplateIntegration/P1UIVisibility.swift").unlink()
        before = self.snapshot()
        with self.assertRaises(FileNotFoundError):
            MODULE.prepare(self.host, ["http"])
        self.assertEqual(self.snapshot(), before)

    def testMissingDeviceFixtureCannotPartiallyConnectHTTP(self):
        (self.host / "Tests/TemplateIntegration/P1DeviceHTTPFixture.swift").unlink()
        before = self.snapshot()
        with self.assertRaises(FileNotFoundError):
            MODULE.prepare(self.host, ["http"])
        self.assertEqual(self.snapshot(), before)

    def testDeviceFixtureIsSharedAcrossHTTPAndWebButNotRequiredForNotifications(self):
        MODULE.prepare(self.host, ["http"])
        target = self.host / "Sources/JibunKit/P1DeviceHTTPFixture.swift"
        before = target.read_bytes()
        MODULE.prepare(self.host, ["web"])
        self.assertEqual(target.read_bytes(), before)
        (self.host / "Tests/TemplateIntegration/P1DeviceHTTPFixture.swift").unlink()
        MODULE.prepare(self.host, ["notifications"])
        self.assertEqual(target.read_bytes(), before)

    def testChangedHelperCannotBeOverwrittenDuringComposition(self):
        MODULE.prepare(self.host, ["http"])
        (self.host / "UITests/P1UIVisibility.swift").write_text("// local edits", encoding="utf-8")
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "changed UI helper"):
            MODULE.prepare(self.host, ["web"])
        self.assertEqual(self.snapshot(), before)

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
