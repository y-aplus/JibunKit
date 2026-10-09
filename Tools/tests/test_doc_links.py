import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('check_doc_links', ROOT / 'Tools/check-doc-links.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DocLinkTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        return path

    def testSlugsFollowGitHubHeadingRules(self):
        self.assertEqual(MODULE.slug('2. Connect it to the host'), '2-connect-it-to-the-host')
        self.assertEqual(MODULE.slug('Opening `another` app'), 'opening-another-app')
        self.assertEqual(MODULE.slug('マイナー版の文書・出荷gate'), 'マイナー版の文書出荷gate')

    def testReportsMissingFilesAndHeadingsButNotCodeOrURLs(self):
        self.write('target.md', '# Title\n## Same\n## Same\n<a id="custom"></a>\n```\n# Not a heading\n```\n')
        source = self.write('source.md', '\n'.join([
            '[ok](target.md#title)',
            '[second](target.md#same-1)',
            '[custom](target.md#custom)',
            '[local](#local)',
            '[web](https://example.com/missing)',
            '`[code](missing.md)`',
            '```',
            '[fenced](missing.md)',
            '```',
            '[file](missing.md)',
            '[heading](target.md#not-a-heading)',
            '[ref]: target.md#gone',
            '## Local',
        ]))
        found = [(line, reason) for line, _, reason in MODULE.problems(source)]
        self.assertEqual(found, [(10, 'missing file'), (11, 'missing heading'), (12, 'missing heading')])

    def testCurrentDocumentsHaveNoBrokenLinks(self):
        broken = [(path, problem) for path in MODULE.selected([]) for problem in MODULE.problems(path)]
        self.assertEqual(broken, [])


if __name__ == '__main__':
    unittest.main()
