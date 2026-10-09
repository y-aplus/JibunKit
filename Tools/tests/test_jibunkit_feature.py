import importlib.util
import json
from pathlib import Path
import re
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('jibunkit_feature', ROOT / 'Tools/jibunkit-feature.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class JibunKitFeatureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        shutil.copytree(ROOT / 'Tuist/Templates', self.root / 'Tuist/Templates')

    def tearDown(self):
        self.temporary.cleanup()

    def manifest(self, name='Notes'):
        return self.root / 'Modules' / name / 'JibunKitFeature.json'

    def write_manifest(self, data, name='Notes'):
        self.manifest(name).write_text(json.dumps(data), encoding='utf-8')

    def helper(self):
        return (self.root / MODULE.HELPER).read_text(encoding='utf-8')

    def testNewCreatesEveryTemplateFileAndConnectsTheFeature(self):
        MODULE.new(self.root, 'Notes')
        template = (ROOT / 'Tuist/Templates/feature/feature.swift').read_text(encoding='utf-8')
        expected = {path.replace('\\(name)', 'Notes') for path in re.findall(r'\.file\(path: "([^"]+)"', template)}
        created = {path.relative_to(self.root).as_posix() for path in (self.root / 'Modules').rglob('*') if path.is_file()}
        self.assertEqual(created, expected)
        integration = (self.root / 'Modules/Notes/Integration/NotesMiniApp.swift').read_text(encoding='utf-8')
        self.assertIn('MiniAppID("notes")', integration)
        self.assertNotIn('{{', integration)
        helper = self.helper()
        self.assertIn('id: "notes"', helper)
        self.assertIn('path: "Modules/Notes"', helper)
        self.assertIn('definitions: ["NotesMiniApp.definition"]', helper)
        self.assertFalse(MODULE.sync(self.root, check=True))

    def testNewRefusesInvalidNamesAndExistingDirectories(self):
        for name in ['notes', 'Notes-App', '9Notes', '']:
            with self.assertRaises(MODULE.FeatureError):
                MODULE.new(self.root, name)
        MODULE.new(self.root, 'Notes')
        with self.assertRaises(MODULE.FeatureError):
            MODULE.new(self.root, 'Notes')

    def testEmptyRepositoryRendersTheCommittedStub(self):
        self.assertEqual(MODULE.render([]), (ROOT / MODULE.HELPER).read_text(encoding='utf-8'))

    def testCheckFailsUntilSyncRuns(self):
        MODULE.new(self.root, 'Notes', run_sync=False)
        with self.assertRaises(MODULE.FeatureError):
            MODULE.sync(self.root, check=True)
        self.assertTrue(MODULE.sync(self.root))
        self.assertFalse(MODULE.sync(self.root, check=True))

    def testFeaturesAreOrderedByDirectoryAndIDsMustBeUnique(self):
        MODULE.new(self.root, 'Zeta')
        MODULE.new(self.root, 'Alpha')
        helper = self.helper()
        self.assertLess(helper.index('Modules/Alpha'), helper.index('Modules/Zeta'))
        data = json.loads(self.manifest('Zeta').read_text(encoding='utf-8'))
        data['id'] = 'alpha'
        self.write_manifest(data, 'Zeta')
        with self.assertRaisesRegex(MODULE.FeatureError, 'used by both'):
            MODULE.sync(self.root)

    def testRejectsMistakesBeforeTuistRuns(self):
        MODULE.new(self.root, 'Notes')
        base = json.loads(self.manifest().read_text(encoding='utf-8'))
        cases = {
            'unknown keys': {**base, 'definition': ['NotesMiniApp.definition']},
            'schema': {**base, 'schema': 2},
            'lowercase letter': {**base, 'id': 'Notes'},
            'does not declare': {**base, 'products': ['NoteFeature']},
            'inside the Feature': {**base, 'sources': ['../Other/**']},
            'missing directory': {**base, 'sources': ['Integrations/**']},
            'at least one definition': {**base, 'definitions': []},
            'unsupported value': {**base, 'definitions': ['NotesMiniApp.definition; exit(1)']},
            'host identity': {**base, 'app': {'infoPlist': {'CFBundleIdentifier': 'x'}}},
            'must not be null': {**base, 'app': {'infoPlist': {'NSCameraUsageDescription': None}}},
            'string tables': {**base, 'app': {'localizedInfoPlist': {'ja': {'NSCameraUsageDescription': 1}}}},
            'one file': {**base, 'appShortcuts': {'source': 'Integration'}},
        }
        for message, data in cases.items():
            with self.subTest(message):
                self.write_manifest(data)
                with self.assertRaisesRegex(MODULE.FeatureError, message):
                    MODULE.sync(self.root)

    def testRendersBuildRequirementsWidgetsAndShortcutsAsSwiftLiterals(self):
        MODULE.new(self.root, 'Notes')
        widget_dir = self.root / 'Modules/Notes/Widget'
        widget_dir.mkdir()
        (self.root / 'Modules/Notes/Integration/AppShortcuts.swift.fragment').write_text('// shortcuts\n', encoding='utf-8')
        package = self.root / 'Modules/Notes/Package.swift'
        package.write_text(package.read_text(encoding='utf-8').replace(
            'products: [', 'products: [.library(name: "NotesWidgetKit", targets: ["NotesFeature"]), '), encoding='utf-8')
        data = json.loads(self.manifest().read_text(encoding='utf-8'))
        data['app'] = {
            'infoPlist': {'NSCameraUsageDescription': 'Scan "codes"\\n', 'UIBackgroundModes': ['audio'],
                          'Flag': True, 'Count': 2, 'Empty': {}},
            'localizedInfoPlist': {'ja': {'NSCameraUsageDescription': 'コードを読み取ります'}},
        }
        data['widget'] = {'products': ['NotesWidgetKit'], 'sources': ['Widget/**'], 'widgets': ['NotesWidget()']}
        data['appShortcuts'] = {'source': 'Integration/AppShortcuts.swift.fragment', 'imports': ['AppIntents']}
        self.write_manifest(data)
        MODULE.sync(self.root)
        helper = self.helper()
        self.assertIn('"NSCameraUsageDescription": "Scan \\"codes\\"\\\\n"', helper)
        self.assertIn('"UIBackgroundModes": ["audio"]', helper)
        self.assertIn('"Flag": true, "Count": 2, "Empty": [:]', helper)
        self.assertIn('localizedInfoPlist: ["ja": ["NSCameraUsageDescription": "コードを読み取ります"]]', helper)
        self.assertIn('widgetProducts: ["NotesWidgetKit"]', helper)
        self.assertIn('widgetSources: ["Widget/**"]', helper)
        self.assertIn('widgets: ["NotesWidget()"]', helper)
        self.assertIn('sourceFile: "Modules/Notes/Integration/AppShortcuts.swift.fragment"', helper)
        self.assertNotIn('widget: FeatureBuildRequirement', helper)

    def testCheckReportsStandaloneAppCodeAndHonoursAllowMarkers(self):
        sources = self.root / 'Modules/Notes/Sources/NotesFeature'
        sources.mkdir(parents=True)
        (sources / 'Notes.swift').write_text('\n'.join([
            '@main',
            'let a = UserDefaults.standard',
            'let b = UserDefaults.standard // jibunkit: allow standard-defaults',
            '// UIApplication.shared.open(url)',
            'UIApplication.shared.open(url)',
            '@AppStorage("x") var x = 1',
            '@AppStorage("y", store: shared) var y = 1',
            'Tips.configure()',
            'NavigationStack { // jibunkit: allow navigation-stack, color-scheme',
        ]), encoding='utf-8')
        example = self.root / 'Modules/Notes/Example'
        example.mkdir(parents=True)
        (example / 'App.swift').write_text('@main\nstruct App {}\n', encoding='utf-8')
        found = [(path.name, line, rule) for path, line, rule, _, _ in MODULE.check([self.root / 'Modules/Notes'])]
        self.assertEqual(found, [
            ('Notes.swift', 1, 'app-entry'),
            ('Notes.swift', 2, 'standard-defaults'),
            ('Notes.swift', 5, 'open-url'),
            ('Notes.swift', 6, 'standard-defaults'),
            ('Notes.swift', 8, 'tips-configure'),
        ])

    def testCheckRulesLinkToExistingDocuments(self):
        for rule, _, _, doc in MODULE.CHECKS:
            with self.subTest(rule):
                path, _, anchor = doc.partition('#')
                document = ROOT / path
                self.assertTrue(document.is_file(), doc)
                if anchor:
                    headings = re.findall(r'^#+ (.+)$', document.read_text(encoding='utf-8'), re.MULTILINE)
                    slugs = {re.sub(r'[^\w\- ]', '', heading.lower()).replace(' ', '-') for heading in headings}
                    self.assertIn(anchor, slugs, doc)

    def testSwiftStringEscapesControlCharacters(self):
        self.assertEqual(MODULE.swift_string('a\\b"c\n\t\x01'), '"a\\\\b\\"c\\n\\t\\u{1}"')


if __name__ == '__main__':
    unittest.main()
