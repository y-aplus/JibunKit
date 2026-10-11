import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('check_localization', ROOT / 'Tools/check-localization.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LocalizationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        for table, sources, _ in MODULE.TABLES:
            for directory in sources:
                (self.root / directory).mkdir(parents=True, exist_ok=True)
            self.table(table, {})

    def tearDown(self):
        self.temporary.cleanup()

    def table(self, directory, entries, ja=None):
        for language, values in (('en', {key: key for key in entries}), ('ja', ja if ja is not None else entries)):
            path = self.root / directory / f'{language}.lproj' / 'Localizable.strings'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(''.join(f'"{strings_literal(k)}" = "{strings_literal(v)}";\n' for k, v in values.items()),
                            encoding='utf-8')

    def source(self, path, text):
        (self.root / path).write_text(text, encoding='utf-8')

    def testEveryLocalizedStringNeedsAnEntryAndEveryEntryAUse(self):
        self.table('Sources/JibunKit/Resources', {'Close': '閉じる', 'Old': '古い'})
        self.source('Sources/JibunKit/Screen.swift', '\n'.join([
            'Button("Close") { dismiss() }',
            'Text("Missing")',
            'Text(verbatim: "not localized")',
            '.accessibilityIdentifier("backup.open")',
            '// Text("in a comment")',
        ]))
        self.assertEqual(MODULE.check(self.root), [
            "Sources/JibunKit/Screen.swift:2: 'Missing' has no entry in Sources/JibunKit/Resources",
            "Sources/JibunKit/Resources: 'Old' is not used by the source",
        ])

    def testInterpolationsMatchFormatSpecifiersAndNestedLiterals(self):
        self.table('Sources/JibunKit/Resources', {
            'Search for “%@”': '「%@」を検索',
            'Waiting: %lld tasks': '待機: %lld 件',
            'Retry': '再試行',
            'Delete': '削除',
            'Line\nTwo %@': '行\n二 %@',
        })
        self.source('Sources/JibunKit/Screen.swift', '\n'.join([
            '.navigationTitle("Search for “\\(query ?? "")”")',
            'Text("Waiting: \\(count) tasks")',
            'Button(retrying ? "Retry" : "Delete" as LocalizedStringKey) {}',
            'status = String(localized: "Line\\nTwo \\(name)")',
            'DisplayRepresentation(title: "\\(title)")',
        ]))
        self.assertEqual(MODULE.check(self.root), [])

    def testPackageStringsMustNameTheModuleBundle(self):
        self.table('Sources/JibunKitCore/Resources', {'Try Again': '再試行'})
        self.source('Sources/JibunKitCore/View.swift', '\n'.join([
            'Button { retry() } label: { Text("Try Again", bundle: .module) }',
            'Text("Diagnostic only")',
        ]))
        self.assertEqual(MODULE.check(self.root), [])

    def testReportsJapaneseSourceTablesThatDifferAndSpecifierMismatches(self):
        self.table('Sources/JibunKitIncomingExtensionUI/Resources', {'Count %lld': '件数 %@'})
        ja = self.root / 'Sources/JibunKitIncomingExtensionUI/Resources/ja.lproj/Localizable.strings'
        ja.write_text(ja.read_text(encoding='utf-8') + '"Extra" = "追加";\n', encoding='utf-8')
        self.source('Sources/JibunKitIncomingExtensionUI/Screen.swift', 'Text("Count \\(n)")\nText("保存")\n')
        self.assertEqual(MODULE.check(self.root), [
            "Sources/JibunKitIncomingExtensionUI/Resources: 'Extra' is in only one of en.lproj and ja.lproj",
            "Sources/JibunKitIncomingExtensionUI/Resources/ja.lproj: 'Count %lld' and its value use different format specifiers",
            "Sources/JibunKitIncomingExtensionUI/Screen.swift:2: Japanese text in the source; write English and add "
            "the translation to Sources/JibunKitIncomingExtensionUI/Resources/ja.lproj",
        ])

    def testRepositoryTablesMatchTheSource(self):
        self.assertEqual(MODULE.check(ROOT), [])


def strings_literal(text):
    return text.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')


if __name__ == '__main__':
    unittest.main()
