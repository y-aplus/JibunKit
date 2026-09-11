"""Check Counter's public Shortcut contract against its pre-composition IPA."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("metadata", type=Path)
args = parser.parse_args()
baseline_path = Path(__file__).resolve().parents[1] / "Tests/AppShortcuts/CounterBaseline.json"
baseline = json.loads(baseline_path.read_bytes())
actual = json.loads(args.metadata.read_bytes())

assert actual.get("autoShortcutProviderMangledName") == baseline["autoShortcutProviderMangledName"], \
    "Counter Shortcut provider identity changed"
for identifier, expected in baseline["actions"].items():
    assert actual.get("actions", {}).get(identifier) == expected, \
        f"Existing Intent contract changed: {identifier}"
    shortcuts = [item for item in actual.get("autoShortcuts", []) if item["actionIdentifier"] == identifier]
    expected_shortcuts = [item for item in baseline["autoShortcuts"] if item["actionIdentifier"] == identifier]
    assert shortcuts == expected_shortcuts, f"Existing Shortcut contract changed: {identifier}"
print("Counter Shortcut provider, Intent identity, parameters, result, and phrases match pre-composition IPA")
