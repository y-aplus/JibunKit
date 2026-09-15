"""Observe real OS Share representations using the normal host plus two incoming Definitions."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess


def prepare(root):
    registry = root / 'Sources/JibunKit/MiniAppRegistry.swift'
    text = registry.read_text(encoding='utf-8')
    anchor = 'static let all = makeRegistry(['
    if text.count(anchor) != 1 or 'P1IncomingProbe.definitions' in text:
        raise ValueError('Expected unchanged normal Registry')
    changes = {}
    for name, directory in [('P1IncomingProbe.swift', 'Sources/JibunKit'),
                            ('P1IncomingOSDiagnosticUITests.swift', 'UITests')]:
        target = root / directory / name
        if target.exists():
            raise ValueError(f'Refusing to overwrite {target}')
        changes[target] = (root / 'Tests/TemplateIntegration' / name).read_bytes()
    changes[registry] = text.replace(anchor, anchor + '\n        P1IncomingProbe.definitions[0],\n        P1IncomingProbe.definitions[1],', 1).encode('utf-8')
    for path, content in changes.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator-id', required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = Path(os.environ['RUNNER_TEMP']) / 'IncomingOS'
    root = output / 'host'
    root.mkdir(parents=True, exist_ok=False)
    # Only tracked checkout files, excluding local ignored Features/data.
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=repo).decode().split('\0')
    for name in filter(None, tracked):
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(repo / name, target)
    prepare(root)
    subprocess.run(['tuist', 'generate', '--no-open'], cwd=root, check=True)
    with (output / 'tests.log').open('w', encoding='utf-8') as log:
        result = subprocess.run([
            'xcodebuild', 'test', '-workspace', 'JibunKit.xcworkspace', '-scheme', 'MigrationUITests',
            '-destination', f'platform=iOS Simulator,id={args.simulator_id}',
            '-derivedDataPath', str(output / 'DerivedData'),
            '-resultBundlePath', str(output / 'Tests.xcresult'),
            '-only-testing:MigrationUITests/P1IncomingOSDiagnosticUITests',
            '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=YES',
            'CODE_SIGN_IDENTITY=-', 'CODE_SIGN_STYLE=Manual',
        ], cwd=root, stdout=log, stderr=subprocess.STDOUT)
    lines = (output / 'tests.log').read_text(encoding='utf-8', errors='replace').splitlines()
    print('\n'.join(line for line in lines if any(marker in line for marker in
        ['OS_SHARE', 'share.error', 'Test Case ', 'error:', 'Executed '])))
    if result.returncode:
        print('\n'.join(lines[-35:]))
    else:
        for name in ['testTextShare', 'testURLShare', 'testFileShare']:
            subprocess.run(['python3', str(repo / 'Tools/validate-focused-ui-test.py'),
                'MigrationUITests/P1IncomingOSDiagnosticUITests/' + name,
                '--source-root', str(root / 'UITests'), '--log', str(output / 'tests.log')], check=True)
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
