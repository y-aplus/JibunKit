"""Compare one built target's localized InfoPlist tables with its generated inputs."""
import argparse
from pathlib import Path
import plistlib


def tables(directory):
    if not directory.is_dir():
        raise ValueError(f"Missing localization directory: {directory}")
    result = {}
    for path in sorted(directory.glob("*.lproj/InfoPlist.strings")):
        with path.open("rb") as source:
            values = plistlib.load(source)
        if not isinstance(values, dict) or not all(
            isinstance(key, str) and isinstance(value, str) for key, value in values.items()
        ):
            raise ValueError(f"Expected a string table: {path}")
        result[path.parent.name] = values
    return result


def verify(resources, bundle):
    expected = tables(resources)
    actual = tables(bundle)
    if expected.keys() != actual.keys():
        raise ValueError(
            f"{bundle.name}: localization mismatch; "
            f"missing={sorted(expected.keys() - actual.keys())}, "
            f"unexpected={sorted(actual.keys() - expected.keys())}"
        )
    for locale, values in expected.items():
        if values != actual[locale]:
            keys = values.keys() | actual[locale].keys()
            changed = sorted(key for key in keys if values.get(key) != actual[locale].get(key))
            raise ValueError(f"{bundle.name}: {locale} differs at keys {changed}")
    print(f"{bundle.name}: {len(expected)} localized InfoPlist tables match generated target inputs")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("resources", type=Path)
    parser.add_argument("bundle", type=Path)
    args = parser.parse_args()
    try:
        verify(args.resources, args.bundle)
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        raise SystemExit(str(error)) from error
