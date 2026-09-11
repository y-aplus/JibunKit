"""Keep the native compatibility gate strict except for observed input-type order."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASELINE = json.loads((ROOT / "Tests/AppShortcuts/CounterBaseline.json").read_bytes())


class HostShortcutCompatibilityTests(unittest.TestCase):
    def check_metadata(self, metadata, succeeds):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "metadata.json"
            path.write_text(json.dumps(metadata), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "Tools/verify-host-shortcut-compatibility.py"), str(path)],
                capture_output=True, text=True,
            )
        self.assertEqual(result.returncode == 0, succeeds, result.stdout + result.stderr)

    def test_native_input_type_reordering_preserves_contract(self):
        metadata = copy.deepcopy(BASELINE)
        metadata["actions"]["AddCounterValueIntent"]["parameters"][0]["resolvableInputTypes"].reverse()
        self.check_metadata(metadata, True)

    def test_contract_changes_remain_rejected(self):
        for change in ("type-removed", "type-duplicated", "identity", "result", "phrase", "provider"):
            with self.subTest(change=change):
                metadata = copy.deepcopy(BASELINE)
                action = metadata["actions"]["AddCounterValueIntent"]
                types = action["parameters"][0]["resolvableInputTypes"]
                if change == "type-removed":
                    types.pop()
                elif change == "type-duplicated":
                    types.append(copy.deepcopy(types[0]))
                elif change == "identity":
                    action["fullyQualifiedTypeName"] = "Changed.Intent"
                elif change == "result":
                    action["outputType"] = {}
                elif change == "phrase":
                    metadata["autoShortcuts"][0]["phraseTemplates"][0]["key"] = "Changed phrase"
                else:
                    metadata["autoShortcutProviderMangledName"] = "ChangedProvider"
                self.check_metadata(metadata, False)
