#!/usr/bin/env python3
"""Check that relative Markdown links point to existing files and headings.

Usage: python3 Tools/check-doc-links.py [FILE_OR_DIRECTORY ...]
Without arguments it checks the current documents: README, CONTRIBUTING,
SECURITY, CHANGELOG, docs/*.md, docs/guides and docs/releases. Dated
verification records and history stay as they were written and are not checked
by default. External URLs are not fetched.
"""
from pathlib import Path
import re
import sys
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
DEFAULT = ["README.md", "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md", "docs/*.md",
           "docs/guides/*.md", "docs/releases/*.md", "Modules/*/README.md"]
INLINE = re.compile(r"!?\[(?:[^\]\[]|\[[^\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
REFERENCE = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s+.*)?$")
HEADING = re.compile(r"^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$")
HTML_ID = re.compile(r"""<a\s+(?:name|id)=["']([^"']+)["']""")


def slug(text):
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    return re.sub(r"[^\w\- ]", "", text.strip().lower()).replace(" ", "-")


def anchors(path, cache={}):
    if path not in cache:
        found, counts, fenced = set(), {}, False
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.lstrip().startswith(("```", "~~~")):
                fenced = not fenced
                continue
            if fenced:
                continue
            found.update(HTML_ID.findall(line))
            match = HEADING.match(line)
            if match:
                base = slug(match.group(2))
                count = counts.get(base, 0)
                counts[base] = count + 1
                found.add(base if count == 0 else f"{base}-{count}")
        cache[path] = found
    return cache[path]


def links(path):
    fenced = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith(("```", "~~~")):
            fenced = not fenced
            continue
        if fenced:
            continue
        code_free = re.sub(r"`[^`]*`", "", line)
        for target in INLINE.findall(code_free):
            yield number, target
        match = REFERENCE.match(code_free)
        if match:
            yield number, match.group(1)


def problems(path):
    for number, target in links(path):
        if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.IGNORECASE):
            continue
        file_part, _, anchor = target.partition("#")
        file_part = unquote(file_part)
        if file_part.startswith("/"):
            destination = ROOT / file_part.lstrip("/")
        elif file_part:
            destination = (path.parent / file_part)
        else:
            destination = path
        destination = destination.resolve()
        if not destination.exists():
            yield number, target, "missing file"
        elif anchor and destination.suffix.lower() == ".md" and unquote(anchor) not in anchors(destination):
            yield number, target, "missing heading"


def selected(arguments):
    patterns = arguments or DEFAULT
    paths = []
    for pattern in patterns:
        candidate = ROOT / pattern
        if candidate.is_dir():
            paths += sorted(candidate.rglob("*.md"))
        elif any(character in pattern for character in "*?["):
            paths += sorted(ROOT.glob(pattern))
        else:
            paths.append(Path(pattern).resolve() if Path(pattern).is_absolute() else candidate)
    return [path for path in dict.fromkeys(paths) if path.is_file()]


def main(argv):
    found = 0
    paths = selected(argv)
    for path in paths:
        for number, target, reason in problems(path):
            found += 1
            print(f"{path.relative_to(ROOT).as_posix()}:{number}: {reason}: {target}")
    print(f"{found} broken link(s) in {len(paths)} file(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
