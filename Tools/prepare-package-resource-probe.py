#!/usr/bin/env python3
import argparse
import shutil
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("a", "b", "combined"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    (output / "Sources").mkdir(exist_ok=True)
    (output / "UITests").mkdir(exist_ok=True)
    for name in ("FeatureA", "FeatureB"):
        destination = output / "Packages" / name
        if destination.exists():
            shutil.rmtree(destination)
        if name[-1].lower() in args.mode or args.mode == "combined":
            shutil.copytree(root / "Tests" / "PackageResources" / name, destination)

    imports = []
    expressions = []
    expected_english = []
    expected_japanese = []
    dependencies = []
    packages = []
    for owner in ("A", "B"):
        if owner.lower() not in args.mode and args.mode != "combined":
            continue
        module = f"ResourceFeature{owner}"
        imports.append(f"import {module}")
        expressions.extend([
            f'try {module}Values.jsonOwner()',
            f'{module}Values.greeting()',
            f'{module}Values.explicitGreeting(locale: "en")',
            f'{module}Values.explicitGreeting(locale: "ja")',
        ])
        expected_english.extend([owner, f"Hello from {owner}", f"Hello from {owner}", f"{owner}からこんにちは"])
        expected_japanese.extend([owner, f"{owner}からこんにちは", f"Hello from {owner}", f"{owner}からこんにちは"])
        dependencies.append(f'.package(product: "{module}")')
        packages.append(f'.package(path: "Packages/Feature{owner}")')

    app = f'''import SwiftUI
{chr(10).join(imports)}

@main
struct PackageResourceProbeApp: App {{
    var body: some Scene {{ WindowGroup {{ ProbeView() }} }}
}}

struct ProbeView: View {{
    var body: some View {{ Text(result).accessibilityIdentifier("package-resource.result") }}
    private var result: String {{
        do {{
            let actual = [{', '.join(expressions)}]
            let expected = Locale.preferredLanguages.first?.hasPrefix("ja") == true
                ? {expected_japanese!r} : {expected_english!r}
            return actual == expected ? "passed: {args.mode} " + actual.joined(separator: "|") : "failed: {args.mode} " + actual.joined(separator: "|")
        }} catch {{ return "failed: {args.mode} \\(error)" }}
    }}
}}
'''.replace("'", '"')
    (output / "Sources" / "App.swift").write_text(app, encoding="utf-8")
    shutil.copyfile(root / "Tests" / "PackageResources" / "PackageResourceUITests.swift", output / "UITests" / "PackageResourceUITests.swift")

    project = f'''import ProjectDescription

let project = Project(
    name: "PackageResourceProbe",
    packages: [{', '.join(packages)}],
    settings: .settings(base: ["SWIFT_VERSION": "6.0"]),
    targets: [
        .target(name: "PackageResourceProbe", destinations: .iOS, product: .app,
                bundleId: "com.jibunkit.package-resource-probe", deploymentTargets: .iOS("26.0"),
                infoPlist: .extendingDefault(with: [
                    "UILaunchScreen": [:],
                    "CFBundleDevelopmentRegion": "en",
                    "CFBundleLocalizations": ["en", "ja"],
                    "CFBundleAllowMixedLocalizations": true,
                ]), sources: ["Sources/**"],
                dependencies: [{', '.join(dependencies)}]),
        .target(name: "PackageResourceUITests", destinations: .iOS, product: .uiTests,
                bundleId: "com.jibunkit.package-resource-probe.uitests", deploymentTargets: .iOS("26.0"),
                infoPlist: .default, sources: ["UITests/**"], dependencies: [.target(name: "PackageResourceProbe")]),
    ],
    schemes: [.scheme(name: "PackageResourceProbe", shared: true,
                      buildAction: .buildAction(targets: ["PackageResourceProbe"]),
                      testAction: .targets(["PackageResourceUITests"], configuration: .debug))]
)
'''
    (output / "Project.swift").write_text(project, encoding="utf-8")


if __name__ == "__main__":
    main()
