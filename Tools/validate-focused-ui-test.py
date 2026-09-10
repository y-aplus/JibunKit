#!/usr/bin/env python3
"""Validate a focused MigrationUITests identifier and, optionally, its XCTest log."""

import argparse
import re
from pathlib import Path


IDENTIFIER = re.compile(
    r"^MigrationUITests/(?P<class>[A-Za-z_][A-Za-z0-9_]*)"
    r"(?:/(?P<method>test[A-Za-z0-9_]+))?$"
)


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("identifier")
    parser.add_argument("--source-root", type=Path, action="append")
    parser.add_argument("--allow-suite", action="store_true")
    parser.add_argument("--log", type=Path)
    args = parser.parse_args()

    match = IDENTIFIER.fullmatch(args.identifier)
    if not match or (match.group("method") is None and not args.allow_suite):
        fail("focused test must be MigrationUITests/<TestClass>/test<TestMethod>")

    class_name = match.group("class")
    method_name = match.group("method")
    class_pattern = re.compile(
        rf"\b(?:final\s+)?class\s+{re.escape(class_name)}\s*:\s*XCTestCase\b"
    )
    method_expression = re.escape(method_name) if method_name else r"test[A-Za-z0-9_]+"
    method_pattern = re.compile(rf"\bfunc\s+{method_expression}\s*\(")
    matching_sources = []
    sources = {source.resolve() for root in (args.source_root or [Path("UITests")])
               for source in root.glob("*.swift")}
    for source in sources:
        text = source.read_text(encoding="utf-8")
        if class_pattern.search(text) and method_pattern.search(text):
            matching_sources.append(source)
    if len(matching_sources) != 1:
        fail(f"test does not identify exactly one UITests source class/method: {args.identifier}")

    if args.log is not None:
        log = args.log.read_text(encoding="utf-8", errors="replace")
        passed = re.compile(
            rf"Test Case '-\[MigrationUITests\.{re.escape(class_name)} "
            rf"{method_expression}\]' passed \("
        ).findall(log)
        if not passed or (method_name is not None and len(passed) != 1):
            fail(f"test has no passing XCTest evidence (or a method ran more than once): {args.identifier}")

    print(f"validated focused UI test: {args.identifier}")


if __name__ == "__main__":
    main()
