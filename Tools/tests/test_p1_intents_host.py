import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("p1_intents_host", ROOT / "Tools/prepare-p1-intents-host.py")
PREPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARE)


class DiagnosticHostTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.host = Path(self.temp.name)
        for name in ["Project.swift", "Package.swift", "Sources/JibunKit/MiniAppRegistry.swift",
                     "Sources/JibunKit/JibunKitApp.swift", "Tests/TemplateIntegration/P1IntentsProbe.swift",
                     "Tests/TemplateIntegration/P1IntentsUITests.swift"]:
            target = self.host / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)

    def snapshot(self):
        return {p.relative_to(self.host).as_posix(): p.read_bytes()
                for p in self.host.rglob("*") if p.is_file()}

    def testExistingProductAndRegistrationsSurviveDiagnosticComposition(self):
        package = (self.host / "Package.swift").read_bytes()
        registry = self.host / "Sources/JibunKit/MiniAppRegistry.swift"
        registry.write_text(registry.read_text(encoding="utf-8").replace(
            "static let all = makeRegistry([", "static let all = makeRegistry([\n        ExistingProbe.definition,"),
            encoding="utf-8")
        PREPARE.prepare(self.host)
        self.assertEqual((self.host / "Package.swift").read_bytes(), package)
        project = (self.host / "Project.swift").read_text(encoding="utf-8")
        self.assertIn('sourceFile: "Sources/CounterIntegration/AppShortcuts.swift.fragment"', project)
        self.assertIn('.target(name: "JibunKitShare-Extension")', project)
        for item in ["ExistingProbe.definition", "CounterMiniApp.definition", "ReminderMiniApp.definition",
                     "P1IntentsProbe.definitionA", "P1IntentsProbe.definitionB"]:
            self.assertIn(item, registry.read_text(encoding="utf-8"))
        app = (self.host / "Sources/JibunKit/JibunKitApp.swift").read_text(encoding="utf-8")
        self.assertLess(app.index("_ = MiniAppRegistry.management"), app.index("P1IntentsProbe.bootstrap()"))
        self.assertTrue((self.host / "UITests/P1IntentsUITests.swift").is_file())

    def testUnknownHostLayoutFailsBeforeAnyMutation(self):
        app = self.host / "Sources/JibunKit/JibunKitApp.swift"
        app.write_text("new incompatible app layout", encoding="utf-8")
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "Expected one host anchor"):
            PREPARE.prepare(self.host)
        self.assertEqual(self.snapshot(), before)

    def testRepeatedPreparationDoesNotDuplicateOrPartlyRewriteHost(self):
        PREPARE.prepare(self.host)
        before = self.snapshot()
        with self.assertRaises(ValueError):
            PREPARE.prepare(self.host)
        self.assertEqual(self.snapshot(), before)
