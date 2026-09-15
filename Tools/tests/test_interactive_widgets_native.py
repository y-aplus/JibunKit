import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "interactive_widgets", ROOT / "Tools/verify-interactive-widgets.py"
)
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


def metadata(owners):
    result = {"actions": {}, "entities": {}, "queries": {}}
    suffixes = {
        "actions": ["Increment", "WidgetConfiguration", "ControlConfiguration"],
        "entities": ["Item"],
        "queries": ["Query"],
    }
    fields = {
        "actions": "fullyQualifiedTypeName",
        "entities": "fullyQualifiedTypeName",
        "queries": "fullyQualifiedIdentifier",
    }
    for owner in owners:
        for section, names in suffixes.items():
            for name in names:
                identity = f"InteractiveFeature{owner}.Feature{owner}{name}"
                result[section][identity] = {fields[section]: identity}
    return result


class InteractiveWidgetsNativeMetadataTests(unittest.TestCase):
    def test_complete_standalone_and_combined_owner_sets_are_accepted(self):
        for label, owners in [("StandaloneA", "A"), ("StandaloneB", "B"), ("Combined", "AB")]:
            with self.subTest(label=label):
                CHECKER.assert_owner_metadata(metadata(owners), owners, label)

    def test_missing_surface_and_cross_owner_leakage_are_rejected(self):
        missing = metadata("A")
        missing["queries"].clear()
        with self.assertRaises(AssertionError):
            CHECKER.assert_owner_metadata(missing, "A", "missing query")

        leaked = metadata("AB")
        with self.assertRaises(AssertionError):
            CHECKER.assert_owner_metadata(leaked, "A", "leaked owner")

    def test_malformed_metadata_section_is_rejected(self):
        malformed = metadata("A")
        malformed["actions"] = []
        with self.assertRaises(AssertionError):
            CHECKER.assert_owner_metadata(malformed, "A", "malformed actions")


if __name__ == "__main__":
    unittest.main()
