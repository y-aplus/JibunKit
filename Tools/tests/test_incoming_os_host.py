import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('incoming_os', ROOT / 'Tools/verify-incoming-os.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class IncomingOSHostTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in ['Project.swift', 'Sources/JibunKit/MiniAppRegistry.swift',
                     'Tests/TemplateIntegration/P1IncomingProbe.swift',
                     'Tests/TemplateIntegration/P1IncomingOSDiagnosticUITests.swift']:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, path)

    def snapshot(self):
        return {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}

    def testAddsOnlyIncomingPairToUnchangedNormalTargets(self):
        before = self.snapshot()
        MODULE.prepare(self.root)
        self.assertEqual((self.root / 'Project.swift').read_bytes(), before[Path('Project.swift')])
        text = (self.root / 'Sources/JibunKit/MiniAppRegistry.swift').read_text(encoding='utf-8')
        for declaration in ['CounterMiniApp.definition', 'ReminderMiniApp.definition',
                            'P1IncomingProbe.definitions[0]', 'P1IncomingProbe.definitions[1]']:
            self.assertEqual(text.count(declaration + ','), 1)
        before_retry = self.snapshot()
        with self.assertRaises(ValueError):
            MODULE.prepare(self.root)
        self.assertEqual(before_retry, self.snapshot())

    def testMissingTestDoesNotPartlyRegisterProbe(self):
        (self.root / 'Tests/TemplateIntegration/P1IncomingOSDiagnosticUITests.swift').unlink()
        before = self.snapshot()
        with self.assertRaises(FileNotFoundError):
            MODULE.prepare(self.root)
        self.assertEqual(before, self.snapshot())
