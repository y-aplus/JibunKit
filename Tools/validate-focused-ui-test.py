#!/usr/bin/env python3
"""Validate a focused MigrationUITests identifier and, optionally, its XCTest log."""

import argparse
import re
from pathlib import Path


IDENTIFIER = re.compile(
    r"^MigrationUITests/(?P<class>[A-Za-z_][A-Za-z0-9_]*)/"
    r"(?P<method>test[A-Za-z0-9_]+)$"
)


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("identifier")
    parser.add_argument("--source-root", type=Path, default=Path("UITests"))
    parser.add_argument("--log", type=Path)
    args = parser.parse_args()

    match = IDENTIFIER.fullmatch(args.identifier)
    if not match:
        fail("focused test must be MigrationUITests/<TestClass>/test<TestMethod>")

    class_name = match.group("class")
    method_name = match.group("method")
    class_pattern = re.compile(
        rf"\b(?:final\s+)?class\s+{re.escape(class_name)}\s*:\s*XCTestCase\b"
    )
    method_pattern = re.compile(rf"\bfunc\s+{re.escape(method_name)}\s*\(")
    matching_sources = []
    for source in args.source_root.glob("*.swift"):
        text = source.read_text(encoding="utf-8")
        if class_pattern.search(text) and method_pattern.search(text):
            matching_sources.append(source)
    if len(matching_sources) != 1:
        fail(f"focused test does not identify exactly one UITests source method: {args.identifier}")

    if args.log is not None:
        log = args.log.read_text(encoding="utf-8", errors="replace")
        passed = re.compile(
            rf"Test Case '-\[MigrationUITests\.{re.escape(class_name)} "
            rf"{re.escape(method_name)}\]' passed \("
        ).findall(log)
        if len(passed) != 1:
            fail(f"focused test did not report exactly one passing XCTest case: {args.identifier}")

    print(f"validated focused UI test: {args.identifier}")


if __name__ == "__main__":
    main()
