import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("app_intents_check", ROOT / "Tools/verify-app-intents-integration.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
FIXTURES = Path(__file__).parent / "fixtures/app-intents-identities"


def inputs(case):
    root = FIXTURES / case
    return (
        [(owner, checker.read_metadata(root / f"Standalone{owner}.json")) for owner in ["A", "B"]],
        checker.read_metadata(root / "Combined.json"),
    )


class AppIntentsIdentityTests(unittest.TestCase):
    def test_actual_native_silent_collision_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "identity collision 'Entry'"):
            checker.check(*inputs("collision"))

    def test_actual_explicit_identifiers_preserve_both_features(self):
        baselines, integrated = inputs("namespaced")
        self.assertEqual(checker.check(baselines, integrated), 8)
        self.assertEqual(checker.check(baselines + [baselines[0]], integrated), 8)

    def test_lost_replaced_or_misrouted_definition_is_rejected(self):
        baselines, integrated = inputs("namespaced")
        key = "com.jibunkit.intent-fixture.a.entry"
        mutations = {
            "missing": lambda data: data["entities"].pop(key),
            "replaced": lambda data: data["entities"][key].update(fullyQualifiedTypeName="IntentFeatureB.Entry"),
            "misrouted": lambda data: data["entities"][key].update(defaultQueryIdentifier="IntentFeatureB.EntryQuery"),
        }
        for label, mutate in mutations.items():
            with self.subTest(label=label):
                changed = copy.deepcopy(integrated)
                mutate(changed)
                with self.assertRaises(ValueError):
                    checker.check(baselines, changed)

    def test_empty_baseline_cannot_produce_false_success(self):
        with self.assertRaisesRegex(ValueError, "no native definitions"):
            checker.check([("empty", {"entities": {}})], {"entities": {}})


if __name__ == "__main__":
    unittest.main()
