"""Source ancestry must resolve, and a selected method must actually pass once."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[1] / 'validate-focused-ui-test.py'


class FocusedUIValidationTests(unittest.TestCase):
    def validate(self, base, log):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'Support.swift').write_text(base, encoding='utf-8')
            (root / 'Gallery.swift').write_text(
                'final class Gallery: Support { func testPreview() {} }', encoding='utf-8')
            result = root / 'result.log'
            result.write_text(log, encoding='utf-8')
            return subprocess.run([sys.executable, str(TOOL),
                'MigrationUITests/Gallery/testPreview', '--source-root', str(root),
                '--log', str(result)], capture_output=True, text=True).returncode

    def testSubclassRequiresResolvedBaseAndOnePassingExecution(self):
        passed = "Test Case '-[MigrationUITests.Gallery testPreview]' passed (1.0 seconds).\n"
        self.assertEqual(self.validate('class Support: XCTestCase {}', passed), 0)
        for base, log in [('', passed), ('class Support: NSObject {}', passed),
                          ('class Support: Gallery {}', passed),
                          ('class Support: XCTestCase {} class Support: XCTestCase {}', passed),
                          ('class Support: XCTestCase {}', ''),
                          ('class Support: XCTestCase {}', passed * 2)]:
            with self.subTest(base=base, log=log):
                self.assertNotEqual(self.validate(base, log), 0)
