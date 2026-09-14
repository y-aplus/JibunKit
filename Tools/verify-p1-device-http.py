"""Build an iOS-hosted, real-network test target for the diagnostic-only listener."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator-id', required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
output = Path(os.environ['RUNNER_TEMP']) / 'P1DeviceHTTP'
output.mkdir(exist_ok=True)
test_source = repo / 'Tests/TemplateIntegration/P1DeviceHTTPFixtureTests.swift'
methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', test_source.read_text(encoding='utf-8'))
if not methods or len(methods) != len(set(methods)):
    raise SystemExit('Missing or duplicate fixture test methods')
with tempfile.TemporaryDirectory(prefix='p1-device-http-') as temporary:
    root = Path(temporary)
    (root / 'Tuist').mkdir()
    shutil.copyfile(repo / 'Tests/P1DeviceHTTP/Project.swift.fixture', root / 'Project.swift')
    shutil.copyfile(repo / 'Tests/P1DeviceHTTP/App.swift', root / 'App.swift')
    for name in ['P1DeviceHTTPFixture.swift', 'P1DeviceHTTPFixtureTests.swift']:
        shutil.copyfile(repo / 'Tests/TemplateIntegration' / name, root / name)
    subprocess.run(['tuist', 'generate', '--no-open'], cwd=root, check=True)
    with (output / 'tests.log').open('w', encoding='utf-8') as log:
        result = subprocess.run([
            'xcodebuild', 'test', '-workspace', 'P1DeviceHTTP.xcworkspace', '-scheme', 'P1DeviceHTTP',
            '-destination', f'platform=iOS Simulator,id={args.simulator_id}',
            '-derivedDataPath', str(root / 'DerivedData'),
            '-resultBundlePath', str(output / 'Tests.xcresult'),
            '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-',
            'CODE_SIGN_STYLE=Manual',
        ], cwd=root, stdout=log, stderr=subprocess.STDOUT)
    log = (output / 'tests.log').read_text(encoding='utf-8', errors='replace')
    if result.returncode:
        print('\n'.join(log.splitlines()[-100:]))
        raise SystemExit(result.returncode)
    for method in methods:
        pattern = rf"Test Case '-\[(?:\w+\.)?P1DeviceHTTPFixtureTests {re.escape(method)}\]' passed \("
        if len(re.findall(pattern, log)) != 1:
            raise SystemExit(f'Expected exactly one fixture pass: {method}')
    (output / 'tests.json').write_text(json.dumps({'passed': methods}, indent=2)+'\n', encoding='utf-8')
    print(f'P1 device loopback fixture: {len(methods)} real-network tests passed')
