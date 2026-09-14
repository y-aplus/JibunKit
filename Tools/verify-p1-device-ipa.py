"""Check the distributed P1 archive's inventory; this does not prove OS gallery exposure."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import zipfile


def inspect(ipa, version, build):
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None:
            raise ValueError("Corrupt IPA entry")
        names = set(archive.namelist())
        hosts = [n for n in names if n.startswith("Payload/") and n.count("/") == 2 and n.endswith(".app/Info.plist")]
        if len(hosts) != 1:
            raise ValueError("Expected one Payload app")
        app = hosts[0].removesuffix("Info.plist")
        inventories = []
        for suffix, identifier in [("", "com.jibunkit.app"),
                                   ("PlugIns/JibunKitWidget_Extension.appex/", "com.jibunkit.app.Widget"),
                                   ("PlugIns/JibunKitShare_Extension.appex/", "com.jibunkit.app.Share")]:
            prefix = app + suffix
            info = plistlib.loads(archive.read(prefix + "Info.plist"))
            if (info["CFBundleIdentifier"], info["CFBundleShortVersionString"], info["CFBundleVersion"]) != (identifier, version, build):
                raise ValueError("Unexpected identity/version: " + identifier)
            binary = archive.read(prefix + info["CFBundleExecutable"])
            if not binary:
                raise ValueError("Empty executable: " + identifier)
            inventories.append(identifier)
            if identifier.endswith(".Widget"):
                for kind in ["JibunKitCounterWidget", "com.jibunkit.fixture.feature-a.widget", "com.jibunkit.fixture.feature-b.widget"]:
                    if kind.encode() not in binary:
                        raise ValueError("Missing Widget kind in exported binary: " + kind)
                for owner in "AB":
                    bundle = prefix + "JibunKit_P1WidgetFeature" + owner + ".bundle/"
                    for resource in ["Info.plist", "en.lproj/Localizable.strings", "ja.lproj/Localizable.strings"]:
                        if bundle + resource not in names:
                            raise ValueError("Missing exported Widget resource: " + bundle + resource)
        return {"ipa": Path(ipa).name, "sha256": hashlib.sha256(Path(ipa).read_bytes()).hexdigest(),
                "version": version, "build": build, "bundle_ids": inventories,
                "widget_kinds": ["JibunKitCounterWidget", "com.jibunkit.fixture.feature-a.widget", "com.jibunkit.fixture.feature-b.widget"],
                "scope": "Archive CRC, identity/version, executable kind strings and localized resources only; OS gallery/rendering requires separate evidence."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = inspect(args.ipa, args.version, args.build)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))
