"""Compare native package intent metadata in independent and integrated apps."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--simulator-id", required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
fixtures = repo / "Tests/PackageAppIntents"
evidence = Path(os.environ["RUNNER_TEMP"]) / "PackageAppIntents"
evidence.mkdir(exist_ok=True)

def run(command, cwd):
    subprocess.run([str(part) for part in command], cwd=cwd, check=True)

def metadata(app, label):
    paths = list(app.rglob("Metadata.appintents/extract.actionsdata"))
    assert paths, f"No native App Intents metadata: {app}"
    actions = {}
    shortcuts = []
    for index, path in enumerate(paths):
        data = json.loads(path.read_bytes())
        (evidence / f"{label}-{index}.json").write_text(json.dumps(data, indent=2), encoding="utf-8")
        for key, value in data.get("actions", {}).items():
            if key in actions:
                assert actions[key] == value, f"Conflicting native action identifier {key}"
            actions[key] = value
        shortcuts.extend(data.get("autoShortcuts", []))
    return actions, shortcuts

def capture_shortcut_extraction(derived):
    # Keep the compiler's extracted constants for diagnosis if app-level
    # metadata fails to include a Feature-owned shortcut provider.
    for index, path in enumerate(sorted(derived.rglob("*.swiftconstvalues"))):
        destination = evidence / f"const-values-{index}-{path.name}"
        shutil.copyfile(path, destination)
        with (evidence / "const-values-paths.txt").open("a", encoding="utf-8") as listing:
            listing.write(f"{destination.name}: {path.relative_to(derived)}\n")

with tempfile.TemporaryDirectory(prefix="jibunkit-package-intents-") as temp:
    root = Path(temp)
    shutil.copytree(fixtures, root, dirs_exist_ok=True)
    (root / "Tuist").mkdir()
    (root / "Project.swift.fixture").rename(root / "Project.swift")
    run(["tuist", "generate", "--no-open"], root)
    derived = root / "DerivedBuild"
    results = {}
    schemes = ["StandaloneA", "StandaloneB", "Combined",
               "OwnedShortcutsA", "OwnedShortcutsB", "OwnedShortcutsCombined"]
    for scheme in schemes:
        try:
            run(["xcodebuild", "build", "-workspace", root / "PackageIntents.xcworkspace",
                 "-scheme", scheme, "-configuration", "Release", "-destination", "generic/platform=iOS",
                 "-derivedDataPath", derived, "CODE_SIGNING_ALLOWED=NO"], root)
        except subprocess.CalledProcessError:
            capture_shortcut_extraction(derived)
            raise
        results[scheme] = metadata(derived / f"Build/Products/Release-iphoneos/{scheme}.app", scheme)
    capture_shortcut_extraction(derived)

    a, _ = results["StandaloneA"]
    b, _ = results["StandaloneB"]
    combined, shortcuts = results["Combined"]
    for owner, standalone in [("A", a), ("B", b)]:
        suffix = f"Feature{owner}AddValueIntent"
        identifiers = [key for key, value in standalone.items()
                       if value["fullyQualifiedTypeName"] == f"IntentFeature{owner}.{suffix}"]
        assert len(identifiers) == 1, (owner, standalone)
        key = identifiers[0]
        assert key in combined, (key, combined)
        # Host bundle identities can legitimately differ; action identity,
        # parameter/result semantics, title and execution mode must survive.
        for field in ["identifier", "fullyQualifiedTypeName", "title", "parameters", "outputType", "supportedModes"]:
            assert standalone[key][field] == combined[key][field], (key, field)
        assert any(item["actionIdentifier"] == key for item in shortcuts), (key, shortcuts)
        other = b if owner == "A" else a
        assert key not in other, f"Foreign package action leaked into independent {owner} baseline"
    assert len(a) == 1 and len(b) == 1 and len(combined) == 2, (a.keys(), b.keys(), combined.keys())
    print("Native package App Intents metadata: independent A/B match combined actions and both App Shortcuts", flush=True)

    # Inspect the app-level output specifically. Combining metadata from all
    # embedded bundles could falsely hide missing host shortcut registration.
    owned = {}
    for scheme in schemes[3:]:
        path = derived / f"Build/Products/Release-iphoneos/{scheme}.app/Metadata.appintents/extract.actionsdata"
        assert path.is_file(), f"Missing app-level shortcut metadata: {path}"
        data = json.loads(path.read_bytes())
        owned[scheme] = data
        print(f"Package shortcut provider {scheme}: provider={data.get('autoShortcutProviderMangledName')} "
              f"shortcuts={data.get('autoShortcuts', [])}", flush=True)

    merged = owned["OwnedShortcutsCombined"]
    expected_shortcuts = {}
    for owner in ["A", "B"]:
        standalone = owned[f"OwnedShortcuts{owner}"]
        shortcuts = standalone.get("autoShortcuts", [])
        assert len(shortcuts) == 1, (owner, shortcuts)
        shortcut = shortcuts[0]
        key = shortcut["actionIdentifier"]
        assert key not in expected_shortcuts, f"Package shortcut identity collision: {key}"
        expected_shortcuts[key] = shortcut
        assert standalone["actions"][key]["fullyQualifiedTypeName"] == f"IntentFeature{owner}.Feature{owner}AddValueIntent"
        assert merged["actions"][key]["fullyQualifiedTypeName"] == standalone["actions"][key]["fullyQualifiedTypeName"]
    actual_shortcuts = merged.get("autoShortcuts", [])
    assert len(actual_shortcuts) == 2, actual_shortcuts
    assert {item["actionIdentifier"]: item for item in actual_shortcuts} == expected_shortcuts, \
        "Package-owned shortcut metadata differs between independent and combined apps"
    print("Package-owned App Shortcuts: both native app-level definitions survive combined inclusion", flush=True)

    result_bundle = evidence / "IntentExecution.xcresult"
    command = ["xcodebuild", "test", "-workspace", root / "PackageIntents.xcworkspace",
               "-scheme", "IntentExecutionTests", "-configuration", "Debug",
               "-destination", f"platform=iOS Simulator,id={args.simulator_id}",
               "-derivedDataPath", root / "SimulatorBuild", "-resultBundlePath", result_bundle,
               "-only-testing:IntentExecutionTests/IntentExecutionTests/testPackageIntentExecutionChangesOnlyItsOwner",
               "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual"]
    result = subprocess.run([str(part) for part in command], cwd=root,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(result.stdout, flush=True)
    (evidence / "execution.log").write_text(result.stdout, encoding="utf-8")
    assert result.returncode == 0, f"Native intent execution failed: {result.returncode}"
    assert "testPackageIntentExecutionChangesOnlyItsOwner]' passed" in result.stdout, "No passing native XCTest evidence"
    print("Native package intent perform() calls preserved owner storage and returned values", flush=True)
