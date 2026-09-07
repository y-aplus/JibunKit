#!/usr/bin/env python3
"""Generate and register a Feature using only the Python standard library."""

import argparse
import difflib
from pathlib import Path
import re
import sys


def swift_string(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') + '"'


def insert_at(text, marker, content):
    if text.splitlines().count(marker) != 1:
        raise ValueError(f"Expected exactly one registration marker: {marker.strip()}")
    return text.replace(marker, content + marker)


def plan(root, name, identifier, title, icon):
    if not re.fullmatch(r"[A-Z][A-Za-z0-9]*", name):
        raise ValueError("Name must start with A-Z and contain only ASCII letters and digits.")
    if not re.fullmatch(r"[a-z][a-z0-9._-]*", identifier):
        raise ValueError("ID must start with a-z and contain only a-z, 0-9, '.', '-', '_'.")
    if not title.strip() or any(ord(c) < 32 for c in title):
        raise ValueError("Title must be nonempty and contain no control characters.")
    if not re.fullmatch(r"[a-z0-9.-]+", icon):
        raise ValueError("Icon must be an SF Symbol name (lowercase letters, digits, dots, hyphens).")
    target = name + "Feature"
    folder = root / "Sources" / target
    # Case-insensitive check also protects projects shared between Windows/macOS/Linux.
    if any(p.name.casefold() == target.casefold() for p in (root / "Sources").iterdir()):
        raise ValueError(f"Feature directory already exists: {target}")
    package = root / "Package.swift"
    registry = root / "Sources/JibunKit/MiniAppRegistry.swift"
    originals = {package: package.read_text(encoding="utf-8"), registry: registry.read_text(encoding="utf-8")}
    if re.search(r'"' + re.escape(target) + r'"', originals[package]):
        raise ValueError(f"Package already mentions target: {target}")
    # Includes ignored, local-only Features so their identities are not reused.
    for source in (root / "Sources").rglob("*.swift"):
        content = source.read_text(encoding="utf-8")
        if re.search(r'MiniAppID\s*\(\s*(?:rawValue\s*:\s*)?"' + re.escape(identifier) + r'"', content):
            raise ValueError(f"ID already declared in {source.relative_to(root)}: {identifier}")
        if re.search(r'\b(?:enum|struct|class|actor|typealias)\s+' + re.escape(name) + r'(?:MiniApp|RootView)\b', content):
            raise ValueError(f"Generated type name already exists in {source.relative_to(root)}")

    updated_package = insert_at(originals[package], "        // jibunkit:feature-targets",
                               f'        .target(name: "{target}", dependencies: ["JibunKitCore"]),\n')
    updated_package = insert_at(updated_package, "                // jibunkit:feature-dependencies",
                               f'                "{target}",\n')
    updated_registry = insert_at(originals[registry], "// jibunkit:feature-imports", f"import {target}\n")
    updated_registry = insert_at(updated_registry, "        // jibunkit:feature-definitions",
                                f"        {name}MiniApp.definition,\n")
    definition = f'''import JibunKitCore

public enum {name}MiniApp {{
    public static let id = MiniAppID({swift_string(identifier)})

    #if os(iOS)
    @MainActor
    public static let definition = MiniAppDefinition(
        id: id,
        title: {swift_string(title)},
        systemImage: {swift_string(icon)}
    ) {{ context in
        {name}RootView(context: context)
    }}
    #endif
}}
'''
    view = f'''#if os(iOS)
import JibunKitCore
import SwiftUI

public struct {name}RootView: View {{
    private let context: MiniAppContext

    public init(context: MiniAppContext) {{
        self.context = context
    }}

    public var body: some View {{
        // The host owns root navigation. Add Feature content here.
        Text({swift_string(title)})
    }}
}}
#endif
'''
    return originals, {package: updated_package, registry: updated_registry,
                       folder / f"{name}Feature.swift": definition, folder / f"{name}RootView.swift": view}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name", help="Swift type prefix, e.g. Notes")
    parser.add_argument("--id", required=True, help="Stable mini-app ID, e.g. notes")
    parser.add_argument("--title", required=True, help="Display title")
    parser.add_argument("--icon", default="square.grid.2x2", help="SF Symbol name")
    parser.add_argument("--dry-run", action="store_true", help="Print the proposed diff without writing")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        originals, changes = plan(root, args.name, args.id, args.title, args.icon)
        for path, content in changes.items():
            relative = path.relative_to(root).as_posix()
            print(''.join(difflib.unified_diff(originals.get(path, '').splitlines(True), content.splitlines(True),
                                             fromfile='a/' + relative, tofile='b/' + relative)), end='')
        if args.dry_run:
            return 0
        # Validate the whole plan before any writes. Recheck existing files too.
        for path, original in originals.items():
            if path.read_text(encoding="utf-8") != original:
                raise ValueError(f"File changed during planning: {path}")
        created = []
        folder = root / "Sources" / (args.name + "Feature")
        folder.mkdir()  # Never reuse/overwrite a preexisting Feature directory.
        try:
            for path, content in changes.items():
                if path not in originals:
                    with path.open('x', encoding='utf-8', newline='\n') as stream:
                        stream.write(content)
                    created.append(path)
            for path in originals:
                path.write_text(changes[path], encoding='utf-8')
        except OSError:
            for path, original in originals.items():
                path.write_text(original, encoding='utf-8')
            for path in created:
                path.unlink()
            folder.rmdir()
            raise
        print("Feature registered. Review the diff, implement its content, and run the build/tests.")
        return 0
    except (ValueError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    sys.exit(main())
