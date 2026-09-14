import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('split_generated_ui', ROOT / 'Tools/split-generated-ui.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SplitGeneratedUITests(unittest.TestCase):
    def testPartitionsAreDisjointAndCoverEveryMethodInOrder(self):
        tests = [f'MigrationUITests/{suite}/testMethod{index}' for index, suite in enumerate(
            ['P1HTTPUITests', 'P1WebUITests', 'P1NotificationsUITests', 'P0ALifetimeUITests'])]
        first = MODULE.select(','.join(tests), 'network').split(',')
        second = MODULE.select(','.join(tests), 'web-management').split(',')
        self.assertEqual(first, [tests[0], tests[2]])
        self.assertEqual(second, [tests[1], tests[3]])
        self.assertFalse(set(first) & set(second))
        self.assertEqual(set(first + second), set(tests))
        self.assertEqual(MODULE.select(','.join(tests), 'all'), ','.join(tests))

    def testRejectsEmptyDuplicateAndSuiteOnlySelections(self):
        for value in ['', 'MigrationUITests/P1WebUITests',
                      'MigrationUITests/P1WebUITests/testA,MigrationUITests/P1WebUITests/testA']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                MODULE.select(value, 'all')

    def testRejectsEmptyShardAndUnknownShard(self):
        for shard in ['network', 'typo']:
            with self.subTest(shard=shard), self.assertRaises(ValueError):
                MODULE.select('MigrationUITests/P1WebUITests/testA', shard)
