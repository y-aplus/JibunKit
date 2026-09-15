"""Register the P2 Widget/Control pair in an isolated copy of the normal host."""
import argparse
from pathlib import Path


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one interactive host anchor: {old}")
    return text.replace(old, new, 1)


def prepare(host):
    host = host.resolve()
    changes = {}
    package = host / "Package.swift"
    text = package.read_text(encoding="utf-8")
    products = "".join(f'        .library(name: "InteractiveFeature{o}", targets: ["InteractiveFeature{o}"]),\n' for o in "AB")
    targets = "".join(f'        .target(name: "InteractiveFeature{o}", dependencies: ["JibunKitCore"], path: "Tests/InteractiveWidgets/Feature{o}/Sources/InteractiveFeature{o}"),\n' for o in "AB")
    text = once(text, "    products: [\n", "    products: [\n" + products)
    changes[package] = once(text, "    targets: [\n", "    targets: [\n" + targets)
    project = host / "Project.swift"
    text = project.read_text(encoding="utf-8")
    deps = ', .package(product: "InteractiveFeatureA"), .package(product: "InteractiveFeatureB")'
    text = once(text, '.target(name: "JibunKitShare-Extension")', '.target(name: "JibunKitShare-Extension")' + deps)
    changes[project] = once(text,
        'entitlements: .dictionary(widgetBuild.entitlements),\n            dependencies: [.package(product: "CounterFeature"), .package(product: "JibunKitCore")]',
        'entitlements: .dictionary(widgetBuild.entitlements),\n            dependencies: [.package(product: "CounterFeature"), .package(product: "JibunKitCore")' + deps + ']')
    registry = host / "Sources/JibunKit/MiniAppRegistry.swift"
    changes[registry] = once(registry.read_text(encoding="utf-8"), 'static let all = makeRegistry([',
        'static let all = makeRegistry([\n        InteractiveProbe.definitions[0],\n        InteractiveProbe.definitions[1],')
    widget = host / "Sources/JibunKitWidget/CounterWidget.swift"
    text = once(widget.read_text(encoding="utf-8"), 'import CounterFeature',
        'import CounterFeature\nimport AppIntents\nimport InteractiveFeatureA\nimport InteractiveFeatureB\n\nstruct InteractiveIntentPackages: AppIntentsPackage {\n    static var includedPackages: [any AppIntentsPackage.Type] { [FeatureAIntents.self, FeatureBIntents.self] }\n}')
    changes[widget] = once(text, '        CounterWidget()',
        '        CounterWidget()\n        FeatureAWidget()\n        FeatureBWidget()\n        FeatureAControl()\n        FeatureBControl()')
    for name, directory in [("InteractiveProbe.swift", "Sources/JibunKit"), ("InteractiveManagementUITests.swift", "UITests")]:
        changes[host / directory / name] = (host / "Tests/InteractiveWidgets" / name).read_text(encoding="utf-8")
    # Validate every anchor before writing any file; failure leaves the copy intact.
    for path, content in changes.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    prepare(parser.parse_args().host)
