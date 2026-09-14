"""Connect selected P1-B probes to one isolated normal-management diagnostic host."""
import argparse
from pathlib import Path


PROBES = {"notifications": "P1Notifications", "http": "P1HTTP", "web": "P1Web"}
ANCHOR = "static let all = makeRegistry(["


def prepare(host, lanes):
    host = host.resolve()
    if not lanes or len(set(lanes)) != len(lanes) or set(lanes) - PROBES.keys():
        raise ValueError("Choose distinct P1-B lanes: notifications, http, web")
    registry = host / "Sources/JibunKit/MiniAppRegistry.swift"
    text = registry.read_text(encoding="utf-8")
    if text.count(ANCHOR) != 1:
        raise ValueError("Expected exactly one normal Registry anchor")
    if '"UITests/**"' not in (host / "Project.swift").read_text(encoding="utf-8"):
        raise ValueError("Expected the normal UITests source glob")
    changes = {}
    definitions = []
    for lane in lanes:
        name = PROBES[lane]
        if name + "Probe." in text:
            raise ValueError(f"{lane} probes already connected")
        for suffix, directory in [("Probe", "Sources/JibunKit"), ("UITests", "UITests")]:
            filename = name + suffix + ".swift"
            source = host / "Tests/TemplateIntegration" / filename
            target = host / directory / filename
            if target.exists():
                raise ValueError(f"Refusing to overwrite existing diagnostic source: {target}")
            changes[target] = source.read_bytes()
        definitions.extend([f"        {name}Probe.ownerADefinition,", f"        {name}Probe.ownerBDefinition,"])
    changes[registry] = text.replace(ANCHOR, ANCHOR + "\n" + "\n".join(definitions), 1).encode("utf-8")
    # Every selected source/anchor must exist before writing. No root package,
    # second manager, bootstrap seed or per-Feature host switch is introduced.
    for target, content in changes.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, type=Path)
    parser.add_argument("--ui-test-filter", required=True)
    args = parser.parse_args()
    lanes = [lane for lane, name in PROBES.items() if name + "UITests" in args.ui_test_filter]
    prepare(args.host, lanes)
