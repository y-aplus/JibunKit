"""Connect the P1 Intent pair in an explicitly supplied diagnostic host checkout.

Does not change the normal product or root Swift package. The independent
Feature packages are direct Tuist dependencies; the adapter is host source.
"""
import argparse
from pathlib import Path


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one host anchor: {old}")
    return text.replace(old, new, 1)


def prepare(host):
    host = host.resolve()
    project = host / "Project.swift"
    registry = host / "Sources/JibunKit/MiniAppRegistry.swift"
    app = host / "Sources/JibunKit/JibunKitApp.swift"
    changes = {}
    text = project.read_text(encoding="utf-8")
    if 'Tests/PackageAppIntents/FeatureA' in text:
        raise ValueError("Intent probes already connected")
    text = replace_once(text, 'packages: [.package(path: ".")',
                        'packages: [.package(path: "."), '
                        '.package(path: "Tests/PackageAppIntents/FeatureA"), '
                        '.package(path: "Tests/PackageAppIntents/FeatureB")')
    text = replace_once(text, '.target(name: "JibunKitShare-Extension")]',
                        '.target(name: "JibunKitShare-Extension"), '
                        '.package(product: "IntentFeatureA"), .package(product: "IntentFeatureB")]')
    text = replace_once(text, 'try FeatureAppShortcuts.writeProvider([',
                        'try FeatureAppShortcuts.writeProvider([\n'
                        '    FeatureAppShortcuts(owner: "p1-intent-a", imports: ["IntentFeatureA"],\n'
                        '        sourceFile: "Tests/PackageAppIntents/FeatureA/AppShortcuts.swift.fragment"),\n'
                        '    FeatureAppShortcuts(owner: "p1-intent-b", imports: ["IntentFeatureB"],\n'
                        '        sourceFile: "Tests/PackageAppIntents/FeatureB/AppShortcuts.swift.fragment"),')
    changes[project] = text
    changes[registry] = replace_once(registry.read_text(encoding="utf-8"),
        'static let all = makeRegistry([',
        'static let all = makeRegistry([\n        P1IntentsProbe.definitionA,\n        P1IntentsProbe.definitionB,')
    changes[app] = replace_once(app.read_text(encoding="utf-8"),
        'struct JibunKitApp: App {',
        'struct JibunKitApp: App {\n'
        '    init() {\n        _ = MiniAppRegistry.management\n        P1IntentsProbe.bootstrap()\n    }')
    for name, directory in [("P1IntentsProbe.swift", "Sources/JibunKit"),
                            ("P1IntentsUITests.swift", "UITests")]:
        changes[host / directory / name] = (host / "Tests/TemplateIntegration" / name).read_text(encoding="utf-8")
    changes[host / "Sources/JibunKit/P1IntentPackages.swift"] = '''import AppIntents
import IntentFeatureA
import IntentFeatureB

struct P1IntentPackages: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [FeatureAIntentPackage.self, FeatureBIntentPackage.self]
    }
}
'''
    # Validate every anchor/source before writing any file. Reapplying fails
    # explicitly rather than duplicating package/Shortcut/Registry entries.
    for path, content in changes.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, type=Path)
    prepare(parser.parse_args().host)
