import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('jibunkit_feature_import', ROOT / 'Tools/jibunkit-feature.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def git(cwd, *arguments):
    result = subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
                             '-c', 'core.autocrlf=false', *arguments], cwd=cwd, capture_output=True, check=True)
    return result.stdout.decode().strip()


class FeatureImportTests(unittest.TestCase):
    """A host and an upstream repository with a Feature under Features/Notes."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        base = Path(self.temporary.name)
        self.root = base / 'host'
        shutil.copytree(ROOT / 'Tuist/Templates', self.root / 'Tuist/Templates')
        git(self.root, 'init', '-q')
        self.commit(self.root)
        scratch = base / 'scratch'
        shutil.copytree(ROOT / 'Tuist/Templates', scratch / 'Tuist/Templates')
        MODULE.new(scratch, 'Notes', run_sync=False)
        self.upstream = base / 'notes-upstream'
        shutil.copytree(scratch / 'Modules/Notes', self.upstream / 'Features/Notes')
        git(self.upstream, 'init', '-q')
        self.first = self.commit(self.upstream)

    def tearDown(self):
        self.temporary.cleanup()

    def commit(self, repository, message='change'):
        git(repository, 'add', '-A')
        git(repository, 'commit', '-q', '--allow-empty', '-m', message)
        return git(repository, 'rev-parse', 'HEAD')

    def edit(self, path, old, new):
        text = path.read_text(encoding='utf-8')
        self.assertIn(old, text)
        path.write_bytes(text.replace(old, new, 1).encode('utf-8'))

    def add(self):
        MODULE.add_feature(self.root, str(self.upstream), path='Features/Notes')
        MODULE.sync(self.root)
        return self.commit(self.root, 'import')

    def run_main(self, *arguments):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = MODULE.main(['--root', str(self.root), *arguments])
        return status, out.getvalue(), err.getvalue()

    def testAddCopiesTheFeatureRecordsTheCommitAndConnectsIt(self):
        status, out, err = self.run_main('add', str(self.upstream), '--path', 'Features/Notes')
        self.assertEqual(status, 0, err)
        self.assertIn(f'at {self.first} (HEAD) into Modules/Notes: 7 files', out)
        upstream = {p.relative_to(self.upstream / 'Features/Notes'): p.read_bytes()
                    for p in (self.upstream / 'Features/Notes').rglob('*') if p.is_file()}
        copied = {p.relative_to(self.root / 'Modules/Notes'): p.read_bytes()
                  for p in (self.root / 'Modules/Notes').rglob('*') if p.is_file()}
        self.assertEqual(copied, upstream)
        record = json.loads((self.root / MODULE.IMPORTS).read_text(encoding='utf-8'))
        self.assertEqual(record, {'schema': 1, 'features': {'Notes': {
            'repository': str(self.upstream.resolve()), 'ref': 'HEAD', 'commit': self.first, 'path': 'Features/Notes'}}})
        self.assertIn('path: "Modules/Notes"', (self.root / MODULE.HELPER).read_text(encoding='utf-8'))
        self.assertFalse(MODULE.sync(self.root, check=True))

    def testRepositoryShorthandsMeanGitHubOrALocalDirectory(self):
        self.assertEqual(MODULE.repository_url('someone/notes'), 'https://github.com/someone/notes')
        self.assertEqual(MODULE.repository_url('someone/notes.kit'), 'https://github.com/someone/notes.kit')
        self.assertEqual(MODULE.repository_url('https://gitlab.com/someone/notes.git'), 'https://gitlab.com/someone/notes.git')
        self.assertEqual(MODULE.repository_url('git@github.com:someone/notes.git'), 'git@github.com:someone/notes.git')
        self.assertEqual(MODULE.repository_url(str(self.upstream)), str(self.upstream.resolve()))

    def testAddFollowsATagAndRefusesWhatIsNotAFeature(self):
        git(self.upstream, 'tag', 'v1')
        self.edit(self.upstream / 'Features/Notes/Package.swift', 'name: "Notes"', 'name: "NotesKit"')
        self.commit(self.upstream)
        MODULE.add_feature(self.root, str(self.upstream), ref='v1', path='Features/Notes')
        self.assertIn('name: "Notes"', (self.root / 'Modules/Notes/Package.swift').read_text(encoding='utf-8'))
        self.assertEqual(MODULE.load_imports(self.root)['Notes']['commit'], self.first)

        with self.assertRaisesRegex(MODULE.FeatureError, 'not a JibunKit Feature'):
            MODULE.add_feature(self.root, str(self.upstream), path='Features')
        self.assertFalse((self.root / 'Modules/Features').exists())
        broken = self.upstream / 'Broken'
        shutil.copytree(self.upstream / 'Features/Notes', broken)
        (broken / 'JibunKitFeature.json').write_text('{"schema": 2}', encoding='utf-8')
        self.commit(self.upstream)
        with self.assertRaisesRegex(MODULE.FeatureError, 'schema'):
            MODULE.add_feature(self.root, str(self.upstream), path='Broken')
        self.assertFalse((self.root / 'Modules/Broken').exists())
        self.assertEqual(list(MODULE.load_imports(self.root)), ['Notes'])

    def testAddNeedsANameLinkFreeFilesAndANewDirectory(self):
        with self.assertRaisesRegex(MODULE.FeatureError, "'notes-upstream' cannot be a Feature directory name"):
            MODULE.add_feature(self.root, str(self.upstream))
        with self.assertRaisesRegex(MODULE.FeatureError, 'inside the repository'):
            MODULE.add_feature(self.root, str(self.upstream), path='../other')
        with self.assertRaisesRegex(MODULE.FeatureError, 'full 40-character commit hash'):
            MODULE.add_feature(self.root, str(self.upstream), ref=self.first[:7], path='Features/Notes')
        with self.assertRaisesRegex(MODULE.FeatureError, 'Unsupported repository'):
            MODULE.add_feature(self.root, '--upload-pack=touch', name='Notes')
        link = subprocess.run(['git', 'hash-object', '-w', '--stdin'], cwd=self.upstream, input=b'../../secret',
                              capture_output=True, check=True).stdout.decode().strip()
        git(self.upstream, 'update-index', '--add', '--cacheinfo', f'120000,{link},Features/Notes/secret')
        git(self.upstream, 'commit', '-q', '-m', 'link')
        with self.assertRaisesRegex(MODULE.FeatureError, 'secret is a symbolic link'):
            MODULE.add_feature(self.root, str(self.upstream), path='Features/Notes')
        self.assertFalse((self.root / 'Modules/Notes').exists())
        MODULE.add_feature(self.root, str(self.upstream), ref=self.first, path='Features/Notes', name='Memo')
        with self.assertRaisesRegex(MODULE.FeatureError, 'Modules/Memo already exists'):
            MODULE.add_feature(self.root, str(self.upstream), ref=self.first, path='Features/Notes', name='Memo')

    def testUpdateKeepsLocalChangesAndReportsWhatChanged(self):
        self.add()
        local = self.root / 'Modules/Notes/Integration/NotesMiniApp.swift'
        self.edit(local, 'title: "Notes"', 'title: "My Notes"')
        self.commit(self.root)

        feature = self.upstream / 'Features/Notes'
        self.edit(feature / 'Sources/NotesFeature/NotesRootView.swift', 'struct', '/// Shows notes.\npublic struct')
        (feature / 'Sources/NotesFeature/Store.swift').write_text('struct Store {}\n', encoding='utf-8')
        (feature / 'UITests/LaunchTests.swift').unlink()
        with (feature / 'Package.swift').open('a', encoding='utf-8', newline='\n') as file:
            file.write('let extra: Package.Dependency = .package(url: "https://example.com/dep.git", from: "1.0.0")\n')
        manifest = json.loads((feature / 'JibunKitFeature.json').read_text(encoding='utf-8'))
        manifest['app'] = {'infoPlist': {'UIBackgroundModes': ['audio']}}
        (feature / 'JibunKitFeature.json').write_bytes(json.dumps(manifest, indent=2).encode('utf-8'))
        second = self.commit(self.upstream)

        status, out, err = self.run_main('update', 'Notes')
        self.assertEqual(status, 0, err)
        self.assertIn(f'Notes: {self.first[:12]} -> {second[:12]}, 5 file(s) changed', out)
        self.assertIn('  + https://example.com/dep.git', out)
        self.assertIn('  + app infoPlist UIBackgroundModes: audio', out)
        module = self.root / 'Modules/Notes'
        self.assertIn('title: "My Notes"', local.read_text(encoding='utf-8'))
        self.assertIn('/// Shows notes.', (module / 'Sources/NotesFeature/NotesRootView.swift').read_text(encoding='utf-8'))
        self.assertTrue((module / 'Sources/NotesFeature/Store.swift').is_file())
        self.assertFalse((module / 'UITests').exists())
        self.assertEqual(MODULE.load_imports(self.root)['Notes']['commit'], second)

        self.commit(self.root)
        status, out, err = self.run_main('update', 'Notes')
        self.assertEqual(status, 0, err)
        self.assertIn(f'Notes is already at {second}.', out)

    def testUpdateMarksConflictsAndRefusesUncommittedWork(self):
        self.add()
        local = self.root / 'Modules/Notes/Integration/NotesMiniApp.swift'
        self.edit(local, 'title: "Notes"', 'title: "My Notes"')
        with self.assertRaisesRegex(MODULE.FeatureError, 'uncommitted changes'):
            MODULE.update_feature(self.root, 'Notes')
        self.commit(self.root)
        self.edit(self.upstream / 'Features/Notes/Integration/NotesMiniApp.swift', 'title: "Notes"', 'title: "Notebook"')
        self.commit(self.upstream)
        status, _, err = self.run_main('update', 'Notes')
        self.assertEqual(status, 1)
        self.assertIn('conflict: Modules/Notes/Integration/NotesMiniApp.swift', err)
        text = local.read_text(encoding='utf-8')
        self.assertIn('<<<<<<< yours', text)
        self.assertIn('title: "My Notes"', text)
        self.assertIn('title: "Notebook"', text)
        self.assertIn(f'>>>>>>> {git(self.upstream, "rev-parse", "HEAD")[:12]}', text)

    def testRemoveDeletesTheCopyAndSyncNoticesAMissingCopy(self):
        self.add()
        shutil.rmtree(self.root / 'Modules/Notes')
        with self.assertRaisesRegex(MODULE.FeatureError, 'records Notes, but Modules/Notes/JibunKitFeature.json is missing'):
            MODULE.sync(self.root)
        status, out, err = self.run_main('remove', 'Notes')
        self.assertEqual(status, 0, err)
        self.assertFalse((self.root / MODULE.IMPORTS).exists())
        self.assertNotIn('Modules/Notes', (self.root / MODULE.HELPER).read_text(encoding='utf-8'))
        with self.assertRaisesRegex(MODULE.FeatureError, 'not in JibunKitImports.json'):
            MODULE.remove_feature(self.root, 'Notes')

    def testDescribeReadsWhatTheFeatureBringsWithoutRunningIt(self):
        MODULE.new(self.root, 'Notes', run_sync=False)
        module = self.root / 'Modules/Notes'
        (module / 'Package.swift').write_text('\n'.join([
            '// .package(url: "https://example.com/commented.git", from: "1.0.0")',
            'let package = Package(name: "Notes", dependencies: [',
            '    .package(url: "https://example.com/exact.git", exact: "1.2.3"),',
            '    .package(url: "https://example.com/range.git", .upToNextMajor(from: "2.0.0")),',
            '    .package(path: "../Shared"),',
            '    .package(path: "Vendor/Local"),',
            '], targets: [',
            '    .binaryTarget(name: "Fast", url: "https://example.com/fast.zip", checksum: "abc"),',
            '    .macro(name: "NotesMacros", dependencies: []),',
            '    .target(name: "NotesFeature", plugins: [.plugin(name: "Lint", package: "lint")]),',
            '])',
        ]), encoding='utf-8')
        manifest = json.loads((module / 'JibunKitFeature.json').read_text(encoding='utf-8'))
        manifest['app'] = {
            'infoPlist': {'NSCameraUsageDescription': 'Scan', 'UIBackgroundModes': ['audio'],
                          'CFBundleURLTypes': [{'CFBundleURLSchemes': ['notes']}]},
            'entitlements': {'com.apple.developer.healthkit': True},
        }
        (module / 'JibunKitFeature.json').write_text(json.dumps(manifest), encoding='utf-8')
        (module / 'Sources/NotesFeature/Settings.swift').write_text('let d = UserDefaults.standard\n', encoding='utf-8')
        self.assertEqual(MODULE.describe(self.root, module), {
            'Swift packages': ['https://example.com/exact.git exact: "1.2.3"',
                               'https://example.com/range.git .upToNextMajor(from: "2.0.0")',
                               'local ../Shared', 'local Vendor/Local'],
            MODULE.UNPINNED: ['https://example.com/range.git'],
            MODULE.OUTSIDE: ['../Shared'],
            MODULE.BINARY: ['.binaryTarget Fast'],
            MODULE.BUILD_CODE: ['.macro NotesMacros', '.plugin Lint'],
            MODULE.REQUIREMENTS: ['app entitlements com.apple.developer.healthkit',
                                  'app infoPlist CFBundleURLTypes: notes', 'app infoPlist NSCameraUsageDescription',
                                  'app infoPlist UIBackgroundModes: audio'],
            MODULE.FINDINGS: ['Modules/Notes/Sources/NotesFeature/Settings.swift:1 [standard-defaults]'],
        })


if __name__ == '__main__':
    unittest.main()
