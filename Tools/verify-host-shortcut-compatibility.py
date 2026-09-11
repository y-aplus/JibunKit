"""Check Counter's public Shortcut contract against its pre-composition IPA."""
import argparse
import difflib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("metadata", type=Path)
args = parser.parse_args()
baseline_path = Path(__file__).resolve().parents[1] / "Tests/AppShortcuts/CounterBaseline.json"
baseline = json.loads(baseline_path.read_bytes())
actual = json.loads(args.metadata.read_bytes())

def require_equal(actual_value, expected_value, label):
    if actual_value != expected_value:
        print("\n".join(difflib.unified_diff(
            json.dumps(expected_value, ensure_ascii=False, sort_keys=True, indent=2).splitlines(),
            json.dumps(actual_value, ensure_ascii=False, sort_keys=True, indent=2).splitlines(),
            fromfile="pre-composition IPA", tofile="current IPA", lineterm=""
        )), flush=True)
        raise AssertionError(label)

require_equal(actual.get("autoShortcutProviderMangledName"), baseline["autoShortcutProviderMangledName"],
              "Counter Shortcut provider identity changed")
for identifier, expected in baseline["actions"].items():
    require_equal(actual.get("actions", {}).get(identifier), expected,
                  f"Existing Intent contract changed: {identifier}")
    shortcuts = [item for item in actual.get("autoShortcuts", []) if item["actionIdentifier"] == identifier]
    expected_shortcuts = [item for item in baseline["autoShortcuts"] if item["actionIdentifier"] == identifier]
    require_equal(shortcuts, expected_shortcuts, f"Existing Shortcut contract changed: {identifier}")
print("Counter Shortcut provider, Intent identity, parameters, result, and phrases match pre-composition IPA")
