"""Check Counter's public Shortcut contract against its pre-composition IPA."""
import argparse
import copy
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

def normalized_input_types(action):
    # Native extraction changes this allowed-type list's order even when the
    # Intent and hand-written provider sources are unchanged. Keep duplicates
    # and every other array (including parameter/phrase order) intact.
    action = copy.deepcopy(action)
    if isinstance(action, dict):
        for parameter in action.get("parameters", []):
            types = parameter.get("resolvableInputTypes")
            if isinstance(types, list):
                parameter["resolvableInputTypes"] = sorted(types, key=lambda value: json.dumps(value, sort_keys=True))
    return action

for identifier, expected in baseline["actions"].items():
    require_equal(normalized_input_types(actual.get("actions", {}).get(identifier)),
                  normalized_input_types(expected),
                  f"Existing Intent contract changed: {identifier}")
    shortcuts = [item for item in actual.get("autoShortcuts", []) if item["actionIdentifier"] == identifier]
    expected_shortcuts = [item for item in baseline["autoShortcuts"] if item["actionIdentifier"] == identifier]
    require_equal(shortcuts, expected_shortcuts, f"Existing Shortcut contract changed: {identifier}")
print("Counter Shortcut provider, Intent identity, parameters, result, and phrases match pre-composition IPA")
