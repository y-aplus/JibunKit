"""Isolate first-request Core Spotlight behavior without the JibunKit host."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator-id', required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
output = Path(os.environ['RUNNER_TEMP']) / 'SpotlightColdStart'
output.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='spotlight-cold-start-') as temporary:
    root = Path(temporary)
    (root / 'Tuist').mkdir()
    for name in ['Project.swift.fixture', 'App.swift', 'Tests.swift']:
        shutil.copyfile(repo / 'Tests/SpotlightColdStart' / name,
                        root / name.removesuffix('.fixture'))
    subprocess.run(['tuist', 'generate', '--no-open'], cwd=root, check=True)
    with (output / 'tests.log').open('w', encoding='utf-8') as log:
        result = subprocess.run([
            'xcodebuild', 'test', '-workspace', 'SpotlightColdStart.xcworkspace',
            '-scheme', 'SpotlightColdStart',
            '-destination', f'platform=iOS Simulator,id={args.simulator_id}',
            '-derivedDataPath', str(root / 'DerivedData'),
            '-resultBundlePath', str(output / 'Tests.xcresult'),
            '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=YES',
            'CODE_SIGN_IDENTITY=-', 'CODE_SIGN_STYLE=Manual',
        ], cwd=root, stdout=log, stderr=subprocess.STDOUT)
    log = (output / 'tests.log').read_text(encoding='utf-8', errors='replace')
    print('\n'.join(line for line in log.splitlines()
                    if 'SPOTLIGHT_BASELINE' in line or 'Test Case ' in line))
    if result.returncode:
        print('\n'.join(log.splitlines()[-70:]))
    raise SystemExit(result.returncode)
