"""Connect the static Widget pair in a diagnostic checkout using the normal host."""
import argparse
from pathlib import Path


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one Widget host anchor: {old}")
    return text.replace(old, new, 1)


def prepare(host):
    host = host.resolve()
    changes = {}
    package = host / "Package.swift"
    text = package.read_text(encoding="utf-8")
    if "defaultLocalization:" not in text:
        text = once(text, 'name: "JibunKit",', 'name: "JibunKit",\n    defaultLocalization: "en",')
    products = "".join(f'        .library(name: "P1WidgetFeature{n}", targets: ["P1WidgetFeature{n}"]),\n' for n in "AB")
    targets = "".join(f'''        .target(name: "P1WidgetFeature{n}", dependencies: ["JibunKitCore"],
            path: "Tests/PackageWidgets/Feature{n}/Sources/WidgetFeature{n}", resources: [.process("Resources")]),
''' for n in "AB")
    if 'name: "P1WidgetFeatureA"' in text:
        raise ValueError("Widget probes already connected")
    text = once(text, "    products: [\n", "    products: [\n" + products)
    changes[package] = once(text, "    targets: [\n", "    targets: [\n" + targets)
    project = host / "Project.swift"
    text = project.read_text(encoding="utf-8")
    dependencies = ', .package(product: "P1WidgetFeatureA"), .package(product: "P1WidgetFeatureB")'
    text = once(text, '.target(name: "JibunKitShare-Extension")', '.target(name: "JibunKitShare-Extension")' + dependencies)
    changes[project] = once(text,
        'entitlements: .dictionary(widgetBuild.entitlements),\n            dependencies: [.package(product: "CounterFeature"), .package(product: "JibunKitCore")]',
        'entitlements: .dictionary(widgetBuild.entitlements),\n            dependencies: [.package(product: "CounterFeature"), .package(product: "JibunKitCore")' + dependencies + ']')
    registry = host / "Sources/JibunKit/MiniAppRegistry.swift"
    changes[registry] = once(registry.read_text(encoding="utf-8"), 'static let all = makeRegistry([',
        'static let all = makeRegistry([\n        P1WidgetsProbe.definitions[0],\n        P1WidgetsProbe.definitions[1],')
    widget = host / "Sources/JibunKitWidget/CounterWidget.swift"
    text = once(widget.read_text(encoding="utf-8"), 'import CounterFeature',
                'import CounterFeature\nimport P1WidgetFeatureA\nimport P1WidgetFeatureB')
    changes[widget] = once(text, '        CounterWidget()', '        CounterWidget()\n        FeatureAWidget()\n        FeatureBWidget()')
    for name, directory in [("P1WidgetsProbe.swift", "Sources/JibunKit"), ("P1WidgetsUITests.swift", "UITests")]:
        changes[host / directory / name] = (host / "Tests/TemplateIntegration" / name).read_text(encoding="utf-8")
    for path, content in changes.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, type=Path)
    prepare(parser.parse_args().host)
