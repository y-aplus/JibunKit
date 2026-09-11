"""Check that intended native App Intents contributions survive integration.

Inputs are Xcode-produced extract.actionsdata JSON files. This reads identities
and references; it does not generate or rewrite Apple's metadata.
"""
import argparse
import json
from pathlib import Path


IDENTITY_FIELDS = {
    "actions": "fullyQualifiedTypeName",
    "entities": "fullyQualifiedTypeName",
    "queries": "fullyQualifiedIdentifier",
}
REFERENCE_FIELDS = {
    "actions": ("parameters", "outputType"),
    "entities": ("defaultQueryIdentifier", "properties", "typeName"),
    "queries": ("entityType", "resultValueType", "parameters"),
}


def read_metadata(path):
    data = json.loads(path.read_bytes())
    if not isinstance(data, dict) or not any(section in data for section in IDENTITY_FIELDS):
        raise ValueError(f"No recognized native metadata sections: {path}")
    for section in IDENTITY_FIELDS:
        if not isinstance(data.get(section, {}), dict):
            raise ValueError(f"Expected native {section} dictionary: {path}")
    return data


def normalized_references(value):
    # This one order varies across unchanged native builds (see Counter's
    # compatibility experiment). Keep all values and duplicates; other arrays
    # retain their order, including Intent parameters.
    if isinstance(value, dict):
        return {
            key: sorted(item, key=lambda v: json.dumps(v, sort_keys=True))
            if key == "resolvableInputTypes" and isinstance(item, list)
            else normalized_references(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [normalized_references(item) for item in value]
    return value


def check(baselines, integrated):
    expected = {section: {} for section in IDENTITY_FIELDS}
    for label, data in baselines:
        for section, identity_field in IDENTITY_FIELDS.items():
            for identifier, definition in data.get(section, {}).items():
                identity = definition.get(identity_field)
                if not identity:
                    raise ValueError(f"Missing {identity_field}: {label}: {section}.{identifier}")
                previous = expected[section].get(identifier)
                if previous and previous[1][identity_field] != identity:
                    raise ValueError(
                        f"Native {section} identity collision '{identifier}': "
                        f"{previous[1][identity_field]} ({previous[0]}) and {identity} ({label}). "
                        "Use stable, distinct persistentIdentifier values in the owning Features."
                    )
                if previous:
                    for field in REFERENCE_FIELDS[section]:
                        if normalized_references(previous[1].get(field)) != normalized_references(definition.get(field)):
                            raise ValueError(f"Inconsistent baseline {section}.{identifier}.{field}: {label}")
                expected[section][identifier] = (label, definition)

    count = 0
    for section, identity_field in IDENTITY_FIELDS.items():
        for identifier, (label, definition) in expected[section].items():
            actual = integrated.get(section, {}).get(identifier)
            if actual is None:
                raise ValueError(f"Missing integrated {section}.{identifier} from {label}")
            if actual.get(identity_field) != definition[identity_field]:
                raise ValueError(f"Replaced integrated {section}.{identifier}: expected {definition[identity_field]}, got {actual.get(identity_field)}")
            for field in REFERENCE_FIELDS[section]:
                if normalized_references(actual.get(field)) != normalized_references(definition.get(field)):
                    raise ValueError(f"Changed integrated reference {section}.{identifier}.{field} from {label}")
            count += 1
    if not count:
        raise ValueError("Baselines contain no native definitions to verify")
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, action="append", required=True,
                        help="Native contribution metadata intended to remain in the integrated target (repeatable)")
    parser.add_argument("--integrated", type=Path, required=True)
    args = parser.parse_args()
    try:
        count = check([(str(path), read_metadata(path)) for path in args.baseline], read_metadata(args.integrated))
    except (ValueError, OSError) as error:
        parser.exit(1, f"App Intents integration check failed: {error}\n")
    print(f"App Intents integration identities and references preserved: {count} definitions")


if __name__ == "__main__":
    main()
