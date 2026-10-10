#!/usr/bin/env python3
"""Check the host's localized strings against its string tables.

Usage: python3 Tools/check-localization.py

The host screens are written with English text, which is also the key of each
string. Every table below has an en.lproj and a ja.lproj Localizable.strings.
This reports
- a localized string in the Swift source with no entry in a table,
- a table entry that no source string uses any more,
- en and ja tables with different keys, or a translation whose format
  specifiers differ from its key, and
- Japanese text left in the source, which would show untranslated.
Features under Sources/*Feature and Modules/ localize their own text.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent

# Each table and the sources whose strings it holds. `module` marks a Swift
# package target, whose strings name `bundle: .module`.
TABLES = [
    ("Sources/JibunKit/Resources", ["Sources/JibunKit"], False),
    ("Sources/JibunKitCore/Resources", ["Sources/JibunKitCore"], True),
    ("Sources/JibunKitIncomingExtensionUI/Resources", ["Sources/JibunKitIncomingExtensionUI"], False),
]
# Counter's App Intent lives in the host target but belongs to the Counter
# Feature, which keeps its own wording.
UNCHECKED_SOURCES = {"Sources/JibunKit/AddCounterValueIntent.swift"}

VIEW_CALLS = ("Text", "Button", "Label", "Section", "ProgressView", "Toggle", "Picker", "LabeledContent",
              "ContentUnavailableView", "navigationTitle", "accessibilityLabel", "accessibilityHint", "alert")
# App Intents text: titles, descriptions, parameters and display representations.
INTENT_TEXT = (r"(?:LocalizedStringResource|TypeDisplayRepresentation)\s*=\s*", r"IntentDescription\(\s*",
               r"@Parameter\(title:\s*", r"DisplayRepresentation\(title:\s*")
LOCALIZED_BEFORE = re.compile(r"(?:\b(?:%s)\(\s*|String\(localized:\s*|\bprompt:\s*|%s)$"
                              % ("|".join(VIEW_CALLS), "|".join(INTENT_TEXT)))
JAPANESE = re.compile(r"[぀-ヿ㐀-鿿＀-￯]")
SPECIFIER = re.compile(r"%(?:\d+\$)?(@|lld|ld|d|lf|f)")
ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')


class Literal:
    def __init__(self, path, line, parts, start, end):
        self.path, self.line, self.parts, self.start, self.end = path, line, parts, start, end

    def text(self):
        return "".join(part if isinstance(part, str) else "\\(...)" for part in self.parts)

    def pattern(self):
        """A regex for the key: each interpolation becomes a format specifier."""
        return re.compile("".join(re.escape(part) if isinstance(part, str) else "%(?:@|lld|ld|d|lf|f)"
                                  for part in self.parts) + r"\Z")


def unescape(text):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", "0": "\0"}.get(m.group(1), m.group(1)), text)


def literals(source):
    """Yield the single-line string literals in Swift code, outside comments.
    Interpolations are kept as markers, so a key with a nested literal such as
    \\(value ?? "") is read whole."""
    i, line, n = 0, 1, len(source)
    while i < n:
        c = source[i]
        if c == "\n":
            line += 1
        if source.startswith("//", i):
            i = source.find("\n", i)
            i = n if i < 0 else i
            continue
        if source.startswith("/*", i):
            end = source.find("*/", i + 2)
            line += source.count("\n", i, n if end < 0 else end)
            i = n if end < 0 else end + 2
            continue
        if c == '"' and not source.startswith('"""', i):
            start, i, parts, text = i, i + 1, [], ""
            while i < n and source[i] != '"':
                if source.startswith("\\(", i):
                    parts.append(unescape(text))
                    text, depth, i = "", 1, i + 2
                    while i < n and depth:
                        if source[i] == '"':
                            i = source.find('"', i + 1)
                        elif source[i] == "(":
                            depth += 1
                        elif source[i] == ")":
                            depth -= 1
                        i += 1
                    parts.append(None)
                    continue
                if source[i] == "\\":
                    text += source[i:i + 2]
                    i += 2
                    continue
                text += source[i]
                i += 1
            parts.append(unescape(text))
            yield Literal(None, line, [p for p in parts if p != ""], start, i + 1)
            i += 1
            continue
        i += 1


def localized(source, literal, module):
    after = source[literal.end:literal.end + 40]
    if module:
        return re.match(r"\s*,\s*bundle:\s*\.module", after) is not None
    line_start = source.rfind("\n", 0, literal.start) + 1
    line_end = source.find("\n", literal.end)
    if "as LocalizedStringKey" in source[line_start:line_end if line_end >= 0 else None]:
        return True
    return LOCALIZED_BEFORE.search(source[max(0, literal.start - 40):literal.start]) is not None


def read_table(path):
    entries = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.strip().startswith(("/*", "//")):
            continue
        match = ENTRY.match(line)
        if not match:
            raise ValueError(f"{path}:{number}: not a \"key\" = \"value\"; line")
        entries[unescape(match.group(1))] = unescape(match.group(2))
    return entries


def specifiers(text):
    return sorted(SPECIFIER.findall(text))


def check(root=ROOT):
    problems = []
    for table_dir, source_dirs, module in TABLES:
        tables = {language: read_table(root / table_dir / f"{language}.lproj" / "Localizable.strings")
                  for language in ("en", "ja")}
        keys = set(tables["en"])
        if keys != set(tables["ja"]):
            for key in sorted(keys ^ set(tables["ja"])):
                problems.append(f"{table_dir}: {key!r} is in only one of en.lproj and ja.lproj")
        for language, table in tables.items():
            for key, value in table.items():
                if specifiers(key) != specifiers(value):
                    problems.append(f"{table_dir}/{language}.lproj: {key!r} and its value use different format specifiers")
        used = set()
        for source_dir in source_dirs:
            for path in sorted((root / source_dir).rglob("*.swift")):
                relative = path.relative_to(root).as_posix()
                if relative in UNCHECKED_SOURCES:
                    continue
                source = path.read_text(encoding="utf-8")
                for literal in literals(source):
                    if any(JAPANESE.search(part) for part in literal.parts if part):
                        problems.append(f"{relative}:{literal.line}: Japanese text in the source; write English and add "
                                        f"the translation to {table_dir}/ja.lproj")
                        continue
                    if not localized(source, literal, module):
                        continue
                    if all(part is None for part in literal.parts):
                        continue  # only an interpolation, such as a Feature's title
                    matches = [key for key in keys if literal.pattern().match(key)]
                    if not matches:
                        problems.append(f"{relative}:{literal.line}: {literal.text()!r} has no entry in {table_dir}")
                    used.update(matches)
        for key in sorted(keys - used):
            problems.append(f"{table_dir}: {key!r} is not used by the source")
    return problems


def main():
    problems = check()
    for problem in problems:
        print(problem)
    print(f"{len(problems)} localization problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
