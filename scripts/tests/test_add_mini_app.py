from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]


class ScaffoldTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ['Package.swift', 'Sources/JibunKit/MiniAppRegistry.swift',
                     'Sources/CounterFeature/CounterFeature.swift', 'scripts/add-mini-app.py']:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / name, target)

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}

    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(self.root / 'scripts/add-mini-app.py'), *args],
                              capture_output=True, encoding='utf-8')

    def test_dry_run_then_two_additions_preserve_existing_registration(self):
        args = ['Notes', '--id', 'notes.daily', '--title', '日記 "私" \\(value)']
        before = self.snapshot()
        result = self.run_cli(*args, '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, self.snapshot())
        self.assertIn('NotesMiniApp.definition', result.stdout)
        result = self.run_cli(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        generated = (self.root / 'Sources/NotesFeature/NotesFeature.swift').read_text(encoding='utf-8')
        self.assertIn('\\"私\\"', generated)
        self.assertIn('\\\\(value)', generated)
        result = self.run_cli('Tasks', '--id', 'tasks', '--title', 'Tasks')
        self.assertEqual(result.returncode, 0, result.stderr)
        registry = (self.root / 'Sources/JibunKit/MiniAppRegistry.swift').read_text(encoding='utf-8')
        for name in ['Counter', 'Reminder', 'Notes', 'Tasks']:
            self.assertEqual(registry.count(name + 'MiniApp.definition'), 1)

    def test_invalid_inputs_and_duplicate_ids_never_write(self):
        for name, identifier in [('Notes', 'counter'), ('../Escape', 'notes'), ('Notes', '../notes'),
                                 ('Notes', 'Notes'), ('Counter', 'another')]:
            with self.subTest(name=name, identifier=identifier):
                before = self.snapshot()
                result = self.run_cli(name, '--id', identifier, '--title', 'Test')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(before, self.snapshot())

    def test_missing_or_duplicated_marker_never_partially_registers(self):
        path = self.root / 'Sources/JibunKit/MiniAppRegistry.swift'
        original = path.read_text(encoding='utf-8')
        marker = '        // jibunkit:feature-definitions'
        for replacement in ['', marker + '\n' + marker]:
            path.write_text(original.replace(marker, replacement), encoding='utf-8')
            before = self.snapshot()
            result = self.run_cli('Notes', '--id', 'notes', '--title', 'Notes')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(before, self.snapshot())

    def test_rerun_and_local_ignored_feature_are_preserved(self):
        result = self.run_cli('Notes', '--id', 'notes', '--title', 'Notes')
        self.assertEqual(result.returncode, 0, result.stderr)
        before = self.snapshot()
        result = self.run_cli('Notes', '--id', 'different', '--title', 'Notes')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(before, self.snapshot())
        local = self.root / 'Sources/LocalFeature/Local.swift'
        local.parent.mkdir()
        local.write_text('let id = MiniAppID(rawValue: "local.saved")', encoding='utf-8')
        before = self.snapshot()
        result = self.run_cli('Other', '--id', 'local.saved', '--title', 'Other')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(before, self.snapshot())


if __name__ == '__main__':
    unittest.main()
