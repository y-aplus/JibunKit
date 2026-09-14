"""Execute the workflow's real prefix selection with and without an external server."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASH = shutil.which('bash') or ('C:/Program Files/Git/bin/bash.exe' if os.name == 'nt' else None)


@unittest.skipUnless(BASH and Path(BASH).exists(), 'Bash is required for workflow command execution')
class WorkflowCommandPrefixTests(unittest.TestCase):
    def testCommandsForwardArgumentsEnvironmentAndFailureInEveryMode(self):
        workflow = (ROOT / '.github/workflows/build-ios.yml').read_text(encoding='utf-8')
        step = workflow.split('      - name: Test generated Feature in host\n', 1)[1]
        block = step.split('          fixture=', 1)[1].split(' xcodebuild test ', 1)[0]
        prefix = 'fixture=' + block.replace('\n          ', '\n')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            python = shlex.quote(Path(sys.executable).as_posix())
            wrapper = root / 'python3'
            wrapper.write_text(f'#!/bin/bash\nexec {python} "$@"\n', encoding='utf-8', newline='\n')
            wrapper.chmod(0o755)
            path_entry = root.as_posix()
            if os.name == 'nt':
                path_entry = '/' + path_entry[0].lower() + path_entry[2:]
            child = root / 'child.py'
            child.write_text('''import os, sys, urllib.request
assert sys.argv[1] == 'argument with spaces'
mode, code = sys.argv[2:]
if mode == 'embedded':
    assert os.environ['TEST_RUNNER_JIBUNKIT_USE_DEVICE_HTTP_FIXTURE'] == '1'
    assert 'JIBUNKIT_NETWORK_TEST_PORT' not in os.environ
elif mode == 'external':
    port = os.environ['JIBUNKIT_NETWORK_TEST_PORT']
    with urllib.request.urlopen('http://127.0.0.1:' + port + '/echo', timeout=5) as response:
        assert response.status == 200
else:
    assert 'JIBUNKIT_NETWORK_TEST_PORT' not in os.environ
print('child executed', flush=True)
sys.exit(int(code))
''', encoding='utf-8')
            for mode in ['embedded', 'external', 'plain']:
                for code in [0, 7]:
                    with self.subTest(mode=mode, code=code):
                        env = dict(os.environ)
                        for name in ['JIBUNKIT_NETWORK_TEST_PORT', 'TEST_RUNNER_JIBUNKIT_NETWORK_TEST_PORT', 'TEST_RUNNER_JIBUNKIT_USE_DEVICE_HTTP_FIXTURE']:
                            env.pop(name, None)
                        env['P1_DEVICE_VALIDATION'] = 'true' if mode == 'embedded' else 'false'
                        env['FEATURE_UI_TEST_FILTER'] = 'P1HTTPUITests' if mode != 'plain' else 'P1WebUITests'
                        script = ('set -euo pipefail\nexport PATH=' + shlex.quote(path_entry) + ':"$PATH"\n' + prefix
                                  + ' ' + python + ' ' + shlex.quote(child.as_posix())
                                  + f" 'argument with spaces' {mode} {code} | cat\n")
                        result = subprocess.run([BASH, '--noprofile', '--norc', '-c', script],
                                                cwd=ROOT, env=env, capture_output=True, text=True, timeout=15)
                        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                        self.assertIn('child executed', result.stdout)
