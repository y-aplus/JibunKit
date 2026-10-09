#!/usr/bin/env python3
"""Give the generated Notes Feature a widget and build requirements in CI.

The host build then shows whether JibunKitFeature.json reaches the widget
bundle and both Info.plists without editing host files.
"""
import json
from pathlib import Path
import shutil
import sys

module = Path(sys.argv[1])
widget = module / "Widget"
widget.mkdir()
shutil.copyfile(Path(__file__).with_name("ModuleFeatureWidget.swift"), widget / "NotesWidget.swift")
manifest = module / "JibunKitFeature.json"
data = json.loads(manifest.read_text(encoding="utf-8"))
data["app"] = {"infoPlist": {"JibunKitModuleFixture": "notes-app"}}
data["widget"] = {
    "sources": ["Widget/**"],
    "widgets": ["NotesWidget()"],
    "infoPlist": {"JibunKitModuleFixture": "notes-widget"},
}
manifest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
