import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def load_tool(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_tool('jibunkit_feature_migrate', 'Tools/jibunkit-feature.py')
PACKAGE_TESTS = load_tool('test_module_packages_tool', 'Tools/test-module-packages.py')


def git(cwd, *arguments):
    result = subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
                             '-c', 'core.autocrlf=false', *arguments], cwd=cwd, capture_output=True, check=True)
    return result.stdout.decode().strip()


def write(base, name, data):
    path = base / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode('utf-8'))


class MaskTests(unittest.TestCase):
    def testBlanksCommentsAndStringContentsAtTheSamePositions(self):
        text = 'let a = "x(y" // Image("c")\n/* f( /* nested */ ) */ let b = #"r"q"# + """\nm)\n"""\nlet c = "\\(f("i"))"'
        masked = MODULE.mask_code(text)
        self.assertEqual(len(masked), len(text))
        self.assertEqual(masked.count('\n'), text.count('\n'))
        self.assertNotIn('(', masked.replace('\\(', ''))  # Only the interpolation's own parentheses remain masked.
        self.assertNotIn('Image', masked)
        self.assertIn('let b = #"___"#', masked)
        self.assertTrue(masked.startswith('let a = "___"'))


class BundleRewriteTests(unittest.TestCase):
    def rewrite(self, text, localized=True):
        return MODULE.add_module_bundles(text, localized)

    def testAddsTheFeatureBundleWhereTheArgumentBelongs(self):
        text = '\n'.join([
            'Image("logo")',
            'Image("logo", label: Text("L"))',
            'Image("logo", bundle: .main)',
            'Color("Accent")',
            'Text("hello")',
            'Text("hello", tableName: "T", comment: "c")',
            'Text(verbatim: "raw")',
            'Text(String(localized: "Hi \\(name)",',
            '            table: "T"))',
            'NSLocalizedString("bye", comment: "")',
            'NSLocalizedString("bye", tableName: "T", comment: "")',
            'String(localized: "k", defaultValue: "v")',
            'UIImage(named: "pic")',
            'UIImage(named: "pic", in: nil, with: nil)',
            'UIImage(named: "pic", compatibleWith: traits)',
            'UIColor(named: "Accent")',
            '// Image("comment")',
            'let s = "Image(\\"inside\\")"',
        ])
        result, changed, left = self.rewrite(text)
        self.assertEqual(result.split('\n'), [
            'Image("logo", bundle: .module)',
            'Image("logo", bundle: .module, label: Text("L", bundle: .module))',
            'Image("logo", bundle: .main)',
            'Color("Accent", bundle: .module)',
            'Text("hello", bundle: .module)',
            'Text("hello", tableName: "T", bundle: .module, comment: "c")',
            'Text(verbatim: "raw")',
            'Text(String(localized: "Hi \\(name)",',
            '            table: "T", bundle: .module))',
            'NSLocalizedString("bye", bundle: .module, comment: "")',
            'NSLocalizedString("bye", tableName: "T", bundle: .module, comment: "")',
            'String(localized: "k", defaultValue: "v", bundle: .module)',
            'UIImage(named: "pic", in: .module, with: nil)',
            'UIImage(named: "pic", in: nil, with: nil)',
            'UIImage(named: "pic", compatibleWith: traits)',
            'UIColor(named: "Accent", in: .module, compatibleWith: nil)',
            '// Image("comment")',
            'let s = "Image(\\"inside\\")"',
        ])
        self.assertIn(('asset-lookup', 15), left)
        self.assertIn(('localized-text', 5), changed)

    def testTextStaysWithoutLocalizableStrings(self):
        result, _, _ = self.rewrite('Text("hello")', localized=False)
        self.assertEqual(result, 'Text("hello")')


APP = '''import SwiftUI

@main
struct DemoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .modelContainer(for: Item.self)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct Store {}
'''


class RootViewTests(unittest.TestCase):
    def testTheAppBecomesAPublicRootView(self):
        text, notes = MODULE.app_to_root_view(APP, 'DemoRootView', 'dark')
        self.assertIn('public struct DemoRootView: View {', text)
        self.assertIn('@StateObject private var store = Store()', text)
        self.assertIn('    public init() {}\n', text)
        self.assertIn('    public var body: some View {\n        Group {\n            ContentView()\n'
                      '                .environmentObject(store)\n        }\n        .modelContainer(for: Item.self)\n'
                      '        .environment(\\.colorScheme, .dark)\n    }\n}', text)
        self.assertNotIn('@main', text)
        self.assertNotIn('UIApplicationDelegateAdaptor', text)
        self.assertNotIn('.commands', text)
        self.assertIn('struct Store {}', text)
        self.assertEqual(len(notes), 2)
        self.assertIn('dropped the scene modifier .commands', notes[0] + notes[1])
        self.assertIn('`delegate`; move the app delegate', notes[0] + notes[1])

    def testAnExistingInitializerBecomesPublicAndAUsedDelegateIsNamed(self):
        app = APP.replace('    var body', '    init() { setUp() }\n\n    var body').replace(
            'ContentView()', 'delegate.rootView')
        text, notes = MODULE.app_to_root_view(app, 'DemoRootView')
        self.assertIn('    public init() { setUp() }', text)
        self.assertNotIn('public init() {}', text)
        self.assertTrue(any('still uses `delegate`' in note for note in notes))

    def testConditionalModifiersStayAsWritten(self):
        app = APP.replace('        .modelContainer(for: Item.self)\n',
                          '        #if os(macOS)\n        .windowStyle(.hiddenTitleBar)\n        #endif\n'
                          '        .modelContainer(for: Item.self)\n')
        text, _ = MODULE.app_to_root_view(app, 'DemoRootView')
        self.assertIn('        }\n        #if os(macOS)\n        .windowStyle(.hiddenTitleBar)\n        #endif\n'
                      '        .modelContainer(for: Item.self)\n    }', text)

    def testUnusualAppsAreLeftAlone(self):
        cases = {
            'struct DemoApp: App {}': 'no SwiftUI App',
            APP.replace('WindowGroup', 'DocumentGroup'): 'does not start with a WindowGroup',
            APP.replace('        .modelContainer', '        Settings { Text("s") }\n        .modelContainer'):
                'more than one scene',
        }
        for app, reason in cases.items():
            text, result = MODULE.app_to_root_view(app, 'DemoRootView')
            self.assertIsNone(text)
            self.assertIn(reason, result)


# An app in the Xcode 16 format: a folder the target mirrors, minus an exception.
PROJECT = r'''// !$*UTF8*$!
{
	objects = {
		ROOT = {isa = PBXProject; buildConfigurationList = PCL; developmentRegion = en; mainGroup = MAIN;
			packageReferences = (KIT, CORE, ); targets = (APP, ); };
		MAIN = {isa = PBXGroup; children = (FOLDER, ); sourceTree = "<group>"; };
		FOLDER = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (EXCEPT, ); path = Demo; sourceTree = "<group>"; };
		EXCEPT = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (Info.plist, Unused, ); target = APP; };
		PCL = {isa = XCConfigurationList; buildConfigurations = (PRELEASE, ); };
		PRELEASE = {isa = XCBuildConfiguration; name = Release; buildSettings = {SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 18.0; }; };
		APP = {isa = PBXNativeTarget; name = Demo; productType = "com.apple.product-type.application";
			buildConfigurationList = ACL; fileSystemSynchronizedGroups = (FOLDER, );
			packageProductDependencies = (KITPRODUCT, COREPRODUCT, PLUGIN, ); };
		ACL = {isa = XCConfigurationList; buildConfigurations = (ARELEASE, ); };
		ARELEASE = {isa = XCBuildConfiguration; name = Release; buildSettings = {
			INFOPLIST_FILE = Demo/Info.plist;
			INFOPLIST_KEY_CFBundleDisplayName = "Demo Notes";
			INFOPLIST_KEY_NSCameraUsageDescription = "Scan notes";
			INFOPLIST_KEY_NSSupportsLiveActivities = YES;
			INFOPLIST_KEY_UILaunchScreen_Generation = YES;
			CODE_SIGN_ENTITLEMENTS = Demo/Demo.entitlements;
			SWIFT_VERSION = 5.0;
		}; };
		KIT = {isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/example/Kit.git";
			requirement = {kind = upToNextMinorVersion; minimumVersion = 1.2.0; }; };
		CORE = {isa = XCLocalSwiftPackageReference; relativePath = Packages/Core; };
		KITPRODUCT = {isa = XCSwiftPackageProductDependency; package = KIT; productName = Kit; };
		COREPRODUCT = {isa = XCSwiftPackageProductDependency; package = CORE; productName = Core; };
		PLUGIN = {isa = XCSwiftPackageProductDependency; package = KIT; productName = "plugin:Lint"; };
	};
	rootObject = ROOT;
}
'''

VIEW = '''import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image("logo")
            Text("hello")
            Button("Open") { UIApplication.shared.open(url) }
        }
        .onAppear { UserDefaults.standard.set(1, forKey: "k") }
    }
}
'''


class MigrateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        base = Path(self.temporary.name)
        self.root = base / 'host'
        shutil.copytree(ROOT / 'Tuist/Templates', self.root / 'Tuist/Templates')
        git(self.root, 'init', '-q')
        self.upstream = base / 'app'
        up = self.upstream
        write(up, 'Demo.xcodeproj/project.pbxproj', PROJECT)
        write(up, 'Demo/DemoApp.swift', APP)
        write(up, 'Demo/Views/ContentView.swift', VIEW)
        write(up, 'Demo/Unused/Old.swift', 'struct Old {}\n')
        write(up, 'Demo/Legacy.m', '#import <Foundation/Foundation.h>\n')
        write(up, 'Demo/Info.plist', plistlib.dumps({
            'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)', 'UIBackgroundModes': ['audio'],
            'UIAppFonts': ['Demo.ttf'], 'UIUserInterfaceStyle': 'Dark', 'LastUpdate': plistlib.dumps({})[:0] or b'x'}))
        write(up, 'Demo/Demo.entitlements', plistlib.dumps({
            'aps-environment': 'development', 'com.apple.security.application-groups': ['group.demo'],
            'com.apple.developer.healthkit': True}))
        write(up, 'Demo/Assets.xcassets/Contents.json', '{}')
        write(up, 'Demo/Assets.xcassets/logo.imageset/Contents.json', '{}')
        write(up, 'Demo/en.lproj/Localizable.strings', '"hello" = "Hello";\n')
        write(up, 'Demo/ja.lproj/InfoPlist.strings', '/* camera */\n"NSCameraUsageDescription" = "メモを読み取ります";\n'
                                                    'CFBundleDisplayName = "デモ";\n')
        write(up, 'Demo/Sounds/ding.caf', b'\x00\x01')
        write(up, 'Demo/big.png', b'version https://git-lfs.github.com/spec/v1\noid sha256:00\nsize 9\n')
        write(up, '.gitattributes', '*.png filter=lfs diff=lfs merge=lfs -text\n')
        write(up, 'Packages/Core/Package.swift', 'let package = Package(name: "Core")\n')
        write(up, 'Packages/Core/Sources/Core/Core.swift', 'public struct Core {}\n')
        write(up, 'DemoTests/DemoTests.swift', 'import XCTest\n')
        git(up, 'init', '-q')
        git(up, 'add', '-A')
        git(up, 'commit', '-q', '-m', 'app')
        self.commit = git(up, 'rev-parse', 'HEAD')

    def tearDown(self):
        self.temporary.cleanup()

    def run_main(self, *arguments):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = MODULE.main(['--root', str(self.root), *arguments])
        return status, out.getvalue(), err.getvalue()

    def migrate(self):
        status, out, err = self.run_main('migrate', str(self.upstream), '--name', 'Notes')
        self.assertEqual(status, 0, err)
        return self.root / 'Modules/Notes', out

    def testWritesADraftFeatureWithTheMechanicalChanges(self):
        module, out = self.migrate()
        source = module / 'Sources/NotesFeature'
        files = sorted(p.relative_to(source).as_posix() for p in source.rglob('*') if p.is_file())
        self.assertEqual(files, ['Assets.xcassets/Contents.json', 'Assets.xcassets/logo.imageset/Contents.json',
                                 'DemoApp.swift', 'Sounds/ding.caf', 'Views/ContentView.swift',
                                 'en.lproj/Localizable.strings'])
        self.assertFalse((source / 'NotesRootView.swift').exists())
        app = (source / 'DemoApp.swift').read_text(encoding='utf-8')
        self.assertIn('public struct NotesRootView: View {', app)
        self.assertIn('.environment(\\.colorScheme, .dark)', app)
        view = (source / 'Views/ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('Image("logo", bundle: .module)', view)
        self.assertIn('Text("hello", bundle: .module)', view)
        self.assertEqual((module / 'Packages/Core/Sources/Core/Core.swift').read_text(encoding='utf-8'),
                         'public struct Core {}\n')
        package = (module / 'Package.swift').read_text(encoding='utf-8')
        for line in ('defaultLocalization: "en",',
                     '.package(url: "https://github.com/example/Kit.git", .upToNextMinor(from: "1.2.0")),',
                     '.package(path: "Packages/Core"),',
                     '.product(name: "Kit", package: "Kit"),', '.product(name: "Core", package: "Core"),',
                     '.process("Assets.xcassets"),', '.process("Sounds/ding.caf"),', '.process("en.lproj"),',
                     'swiftSettings: [.swiftLanguageMode(.v5)]'):
            self.assertIn(line, package)
        manifest = json.loads((module / 'JibunKitFeature.json').read_text(encoding='utf-8'))
        self.assertEqual(manifest, {
            'schema': 1, 'id': 'notes', 'draft': True, 'products': ['NotesFeature'], 'sources': ['Integration/**'],
            'definitions': ['NotesMiniApp.definition'],
            'app': {'infoPlist': {'NSCameraUsageDescription': 'Scan notes', 'NSSupportsLiveActivities': True,
                                  'UIBackgroundModes': ['audio']},
                    'entitlements': {'com.apple.developer.healthkit': True},
                    'localizedInfoPlist': {'ja': {'NSCameraUsageDescription': 'メモを読み取ります'}}}})
        integration = (module / 'Integration/NotesMiniApp.swift').read_text(encoding='utf-8')
        self.assertIn('MiniAppID("notes")', integration)
        self.assertIn('title: "Demo Notes"', integration)
        report = (module / 'MIGRATION.md').read_text(encoding='utf-8')
        self.assertEqual(out.split('\n\nWrote Modules/Notes')[0] + '\n', report)
        self.assertIn(f'at {self.commit} (HEAD), Xcode project Demo.xcodeproj, target Demo.', report)
        self.assertIn('## Changed', report)
        self.assertIn('## Still to change', report)
        for expected in ('[standard-defaults]', '[open-url]', 'Sources/NotesFeature/Views/ContentView.swift:10',
                         'aps-environment', 'Legacy.m', 'plugin', 'UIAppFonts', 'LastUpdate',
                         'App Groups (group.demo)', '## Not brought from the app',
                         'stored with Git LFS', 'Demo/big.png'):
            self.assertIn(expected, report)

    def testADraftStaysOutOfSyncCheckAndPackageTestsUntilConnected(self):
        module, _ = self.migrate()
        self.assertTrue(MODULE.is_draft(module))
        self.assertTrue(PACKAGE_TESTS.is_draft(module))
        MODULE.sync(self.root)
        self.assertNotIn('Modules/Notes', (self.root / MODULE.HELPER).read_text(encoding='utf-8'))
        status, out, _ = self.run_main('check')
        self.assertEqual(status, 0)
        self.assertIn('0 finding(s) in 0 location(s)', out)
        status, out, _ = self.run_main('sync')
        self.assertIn('Draft, not connected: Modules/Notes', out)

        before = (module / 'JibunKitFeature.json').read_bytes()
        status, _, err = self.run_main('connect', 'Notes')
        self.assertEqual(status, 1)
        self.assertIn('[standard-defaults]', err)
        self.assertEqual((module / 'JibunKitFeature.json').read_bytes(), before)

        status, out, err = self.run_main('connect', 'Notes', '--ignore-check')
        self.assertEqual(status, 0, err)
        self.assertNotIn('draft', json.loads((module / 'JibunKitFeature.json').read_text(encoding='utf-8')))
        self.assertIn('path: "Modules/Notes"', (self.root / MODULE.HELPER).read_text(encoding='utf-8'))
        status, _, err = self.run_main('connect', 'Notes')
        self.assertIn('not a draft', err)

    def testRemoveDeletesADraftButNotAFeatureMadeByHand(self):
        module, _ = self.migrate()
        status, out, err = self.run_main('remove', 'Notes')
        self.assertEqual(status, 0, err)
        self.assertFalse(module.exists())
        MODULE.new(self.root, 'Own', run_sync=False)
        status, _, err = self.run_main('remove', 'Own')
        self.assertEqual(status, 1)
        self.assertIn('is not a draft', err)
        self.assertTrue((self.root / 'Modules/Own').exists())

    def testConnectsOnceCheckIsClean(self):
        module, _ = self.migrate()
        view = module / 'Sources/NotesFeature/Views/ContentView.swift'
        view.write_text(view.read_text(encoding='utf-8')
                        .replace('UIApplication.shared.open(url)', 'open()')
                        .replace('UserDefaults.standard.set(1, forKey: "k")', 'save()'), encoding='utf-8')
        status, out, err = self.run_main('connect', 'Notes')
        self.assertEqual(status, 0, err)
        self.assertIn('Connected Modules/Notes', out)

    def testRefusesExistingNamesAndUnknownApps(self):
        self.migrate()
        status, _, err = self.run_main('migrate', str(self.upstream), '--name', 'Notes')
        self.assertIn('already exists', err)
        status, _, err = self.run_main('migrate', str(self.upstream), '--name', 'Other', '--target', 'Nope')
        self.assertIn("No iOS app target 'Nope'; found: Demo", err)
        empty = Path(self.temporary.name) / 'empty'
        write(empty, 'README.md', 'x')
        git(empty, 'init', '-q')
        git(empty, 'add', '-A')
        git(empty, 'commit', '-q', '-m', 'x')
        status, _, err = self.run_main('migrate', str(empty), '--name', 'Empty')
        self.assertIn('found neither', err)
        self.assertFalse((self.root / 'Modules/Empty').exists())

    def testReportsCollisionsWithConnectedFeatures(self):
        MODULE.new(self.root, 'Notes', run_sync=False)
        status, out, err = self.run_main('migrate', str(self.upstream), '--name', 'Memo', '--id', 'notes')
        self.assertEqual(status, 0, err)
        self.assertIn("The Feature ID 'notes' is also used by Modules/Notes", out)

    def testFilesAddedByExceptionsAndPackagesFoundByProduct(self):
        # A folder the target does not include lists the files it does include;
        # a product without a package reference comes from a package in the repository.
        repository = Path(self.temporary.name) / 'listed'
        write(repository, 'Listed.xcodeproj/project.pbxproj', r'''{ objects = {
            R = {isa = PBXProject; buildConfigurationList = L; mainGroup = G; targets = (T); };
            G = {isa = PBXGroup; children = (APPF, VIEWS, ); sourceTree = "<group>"; };
            APPF = {isa = PBXFileSystemSynchronizedRootGroup; path = App; sourceTree = "<group>"; };
            VIEWS = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (E, ); path = Views; sourceTree = "<group>"; };
            E = {isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (Used.swift, ); target = T; };
            L = {isa = XCConfigurationList; buildConfigurations = (C); };
            C = {isa = XCBuildConfiguration; name = Release; buildSettings = {SDKROOT = iphoneos; SWIFT_VERSION = 6.0; }; };
            T = {isa = PBXNativeTarget; name = Listed; productType = "com.apple.product-type.application";
                 buildConfigurationList = L; fileSystemSynchronizedGroups = (APPF, ); packageProductDependencies = (U, ); };
            U = {isa = XCSwiftPackageProductDependency; productName = Util; };
        }; rootObject = R; }''')
        write(repository, 'App/ListedApp.swift', APP.replace('DemoApp', 'ListedApp'))
        write(repository, 'Views/Used.swift', 'struct Used {}\n')
        write(repository, 'Views/Unused.swift', 'struct Unused {}\n')
        write(repository, 'Modules/Util/Package.swift', 'let package = Package(name: "Util", products: '
              '[.library(name: "Util", targets: ["Util"])], dependencies: [.package(path: "../Base")])\n')
        write(repository, 'Modules/Base/Package.swift', 'let package = Package(name: "Base")\n')
        git(repository, 'init', '-q')
        git(repository, 'add', '-A')
        git(repository, 'commit', '-q', '-m', 'x')
        status, _, err = self.run_main('migrate', str(repository), '--name', 'Listed')
        self.assertEqual(status, 0, err)
        module = self.root / 'Modules/Listed'
        source = module / 'Sources/ListedFeature'
        self.assertEqual(sorted(p.relative_to(source).as_posix() for p in source.rglob('*.swift')),
                         ['App/ListedApp.swift', 'Views/Used.swift'])
        package = (module / 'Package.swift').read_text(encoding='utf-8')
        self.assertIn('.package(path: "Packages/Util"),', package)
        self.assertIn('.product(name: "Util", package: "Util"),', package)
        self.assertTrue((module / 'Packages/Util/Package.swift').is_file())
        self.assertTrue((module / 'Packages/Base/Package.swift').is_file())

    def testClassicProjectsAndPlaygroundsApps(self):
        classic = Path(self.temporary.name) / 'classic'
        write(classic, 'Classic.xcodeproj/project.pbxproj', r'''{ objects = {
            R = {isa = PBXProject; buildConfigurationList = L; mainGroup = G; targets = (T); };
            G = {isa = PBXGroup; children = (SRC, ); sourceTree = "<group>"; };
            SRC = {isa = PBXGroup; children = (A, V, ); path = Classic; sourceTree = "<group>"; };
            A = {isa = PBXFileReference; path = ClassicApp.swift; sourceTree = "<group>"; };
            V = {isa = PBXVariantGroup; children = (VEN, ); name = Localizable.strings; sourceTree = "<group>"; };
            VEN = {isa = PBXFileReference; name = en; path = en.lproj/Localizable.strings; sourceTree = "<group>"; };
            L = {isa = XCConfigurationList; buildConfigurations = (C); };
            C = {isa = XCBuildConfiguration; name = Release; buildSettings = {SDKROOT = iphoneos; SWIFT_VERSION = 6.0; }; };
            T = {isa = PBXNativeTarget; name = Classic; productType = "com.apple.product-type.application";
                 buildConfigurationList = L; buildPhases = (S, RES); };
            S = {isa = PBXSourcesBuildPhase; files = (BA); };
            RES = {isa = PBXResourcesBuildPhase; files = (BV); };
            BA = {isa = PBXBuildFile; fileRef = A; };
            BV = {isa = PBXBuildFile; fileRef = V; };
        }; rootObject = R; }''')
        write(classic, 'Classic/ClassicApp.swift', APP.replace('DemoApp', 'ClassicApp'))
        write(classic, 'Classic/en.lproj/Localizable.strings', '"a" = "A";\n')
        write(classic, 'Classic/NotInTarget.swift', 'struct X {}\n')
        playgrounds = Path(self.temporary.name) / 'play'
        write(playgrounds, 'Play.swiftpm/Package.swift', '// swift-tools-version: 5.9\nimport PackageDescription\n'
              'let package = Package(name: "Play", products: [.iOSApplication(name: "Play", targets: ["AppModule"],\n'
              '    displayName: "Play Time", capabilities: [.camera(purposeString: "Take photos"), .futureThing(purposeString: "Do"), .outgoingNetwork()])],\n'
              '  dependencies: [.package(url: "https://github.com/example/Lib", from: "2.0.0")],\n'
              '  targets: [.executableTarget(name: "AppModule", dependencies: [.product(name: "Lib", package: "lib")], path: ".")])\n')
        write(playgrounds, 'Play.swiftpm/MyApp.swift', APP.replace('DemoApp', 'MyApp'))
        for repository in (classic, playgrounds):
            git(repository, 'init', '-q')
            git(repository, 'add', '-A')
            git(repository, 'commit', '-q', '-m', 'x')
        status, _, err = self.run_main('migrate', str(classic), '--name', 'Classic')
        self.assertEqual(status, 0, err)
        source = self.root / 'Modules/Classic/Sources/ClassicFeature'
        self.assertEqual(sorted(p.name for p in source.rglob('*') if p.is_file()), ['ClassicApp.swift', 'Localizable.strings'])
        self.assertNotIn('swiftLanguageMode', (self.root / 'Modules/Classic/Package.swift').read_text(encoding='utf-8'))
        status, _, err = self.run_main('migrate', str(playgrounds), '--path', 'Play.swiftpm', '--name', 'Play')
        self.assertEqual(status, 0, err)
        module = self.root / 'Modules/Play'
        package = (module / 'Package.swift').read_text(encoding='utf-8')
        self.assertIn('.package(url: "https://github.com/example/Lib", from: "2.0.0"),', package)
        self.assertIn('.product(name: "Lib", package: "lib"),', package)
        self.assertIn('swiftLanguageMode(.v5)', package)
        manifest = json.loads((module / 'JibunKitFeature.json').read_text(encoding='utf-8'))
        self.assertEqual(manifest['app'], {'infoPlist': {'NSCameraUsageDescription': 'Take photos'}})
        self.assertIn('title: "Play Time"', (module / 'Integration/PlayMiniApp.swift').read_text(encoding='utf-8'))
        self.assertIn(".futureThing", (module / 'MIGRATION.md').read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
