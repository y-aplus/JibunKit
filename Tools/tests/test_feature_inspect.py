import contextlib
import importlib.util
import io
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('jibunkit_feature_inspect', ROOT / 'Tools/jibunkit-feature.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

# An app project in the Xcode 16 format: a build configuration taken from a
# mirrored folder, SDK-conditioned settings, and one target of each kind.
PROJECT = r'''// !$*UTF8*$!
{
	archiveVersion = 1;
	objectVersion = 77;
	objects = {
/* Begin PBXProject section */
		ROOT /* Project object */ = {
			isa = PBXProject;
			buildConfigurationList = PCL;
			mainGroup = MAIN;
			packageReferences = (PKGREMOTE, PKGEXACT, PKGLOCAL, PKGOUT, );
			targets = (TAPP, TWIDGET, TKEY, TCLIP, TMAC, TTEST, TFUTURE, TFW, );
		};
/* End PBXProject section */
		MAIN = {isa = PBXGroup; children = (CONFIG, ); sourceTree = "<group>"; };
		CONFIG = {isa = PBXFileSystemSynchronizedRootGroup; path = Config; sourceTree = "<group>"; };
		PCL = {isa = XCConfigurationList; buildConfigurations = (PDEBUG, PRELEASE, ); };
		PDEBUG = {isa = XCBuildConfiguration; name = Debug; buildSettings = {SDKROOT = macosx; }; };
		PRELEASE = {isa = XCBuildConfiguration; name = Release; buildSettings = {
			SDKROOT = iphoneos;
			IPHONEOS_DEPLOYMENT_TARGET = 17.0;
		}; };
		TAPP = {isa = PBXNativeTarget; name = Demo; productType = "com.apple.product-type.application"; buildConfigurationList = ACL; };
		ACL = {isa = XCConfigurationList; buildConfigurations = (ARELEASE, ); };
		ARELEASE = {isa = XCBuildConfiguration; name = Release;
			baseConfigurationReferenceAnchor = CONFIG;
			baseConfigurationReferenceRelativePath = App.xcconfig;
			buildSettings = {
				INFOPLIST_FILE = "$(SRCROOT)/Demo/Info.plist";
				INFOPLIST_KEY_NSCameraUsageDescription = "Scan \"things\"";
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				"INFOPLIST_KEY_NSMicrophoneUsageDescription[sdk=iphoneos*]" = Record;
				"INFOPLIST_KEY_NSMotionUsageDescription[sdk=macosx*]" = "Mac only";
				CODE_SIGN_ENTITLEMENTS = Demo/Demo.entitlements;
				OTHER_SWIFT_FLAGS = ("$(inherited)", "-DDEMO", );
			};
		};
		TWIDGET = {isa = PBXNativeTarget; name = DemoWidgets; productType = "com.apple.product-type.app-extension"; buildConfigurationList = WCL; };
		WCL = {isa = XCConfigurationList; buildConfigurations = (WRELEASE, ); };
		WRELEASE = {isa = XCBuildConfiguration; name = Release; buildSettings = {INFOPLIST_FILE = Widgets/Info.plist; }; };
		TKEY = {isa = PBXNativeTarget; name = Keys; productType = "com.apple.product-type.app-extension"; buildConfigurationList = KCL; };
		KCL = {isa = XCConfigurationList; buildConfigurations = (KRELEASE, ); };
		KRELEASE = {isa = XCBuildConfiguration; name = Release; buildSettings = {INFOPLIST_FILE = Keys/Info.plist; }; };
		TCLIP = {isa = PBXNativeTarget; name = Clip; productType = "com.apple.product-type.application.on-demand-install-capable"; buildConfigurationList = CCL; };
		CCL = {isa = XCConfigurationList; buildConfigurations = (); };
		TMAC = {isa = PBXNativeTarget; name = DemoMac; productType = "com.apple.product-type.application"; buildConfigurationList = MCL; };
		MCL = {isa = XCConfigurationList; buildConfigurations = (MRELEASE, ); };
		MRELEASE = {isa = XCBuildConfiguration; name = Release; buildSettings = {SDKROOT = macosx; }; };
		TTEST = {isa = PBXNativeTarget; name = DemoTests; productType = "com.apple.product-type.bundle.unit-test"; buildConfigurationList = CCL; };
		TFUTURE = {isa = PBXNativeTarget; name = Future; productType = "com.apple.product-type.application"; buildConfigurationList = FCL; };
		FCL = {isa = XCConfigurationList; buildConfigurations = (FRELEASE, ); };
		FRELEASE = {isa = XCBuildConfiguration; name = Release; buildSettings = {IPHONEOS_DEPLOYMENT_TARGET = 27.0; }; };
		TFW = {isa = PBXNativeTarget; name = DemoCore; productType = "com.apple.product-type.framework"; buildConfigurationList = CCL; };
		PKGREMOTE = {isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/example/Kit.git";
			requirement = {kind = upToNextMajorVersion; minimumVersion = 1.2.0; }; };
		PKGEXACT = {isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/example/Exact";
			requirement = {kind = exactVersion; version = 2.0.0; }; };
		PKGLOCAL = {isa = XCLocalSwiftPackageReference; relativePath = Packages/Core; };
		PKGOUT = {isa = XCLocalSwiftPackageReference; relativePath = ../Outside; };
	};
	rootObject = ROOT;
}
'''

APP = '''import SwiftUI
import SwiftData

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(for: Item.self)
    }
}

struct ContentView: View {
    let name = "x"
    var body: some View {
        VStack {
            Image("logo")
            Image("logo", bundle: .module)
            Text("hello")
            Text("hello", bundle: .module)
            Text(String(localized: "Hi \\(name)",
                        bundle: .module))
            Text(NSLocalizedString("bye", comment: ""))
            // Image("commented")
        }
        .onAppear { UserDefaults.standard.set(1, forKey: "k") }
    }
}
'''


def write(base, name, data):
    path = base / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode('utf-8'))


def places(inspection, section, fragment):
    """The places of the one finding in `section` whose message contains `fragment`, or None."""
    found = [where for (kind, message), where in inspection.items.items() if kind == section and fragment in message]
    if len(found) > 1:
        raise AssertionError(f'{fragment!r} matches {len(found)} findings')
    return found[0] if found else None


class ParseOpenStepTests(unittest.TestCase):
    def testReadsTheProjectFileFormat(self):
        data = MODULE.parse_openstep('// !$*UTF8*$!\n{ a = 1; /* note */ b = ("x y", z, ); '
                                     'c = { "d.e" = "q\\"uote\\n"; }; f = <0fbd77>; g = "$(SRCROOT)/x"; h = a.b-c_d/e; }')
        self.assertEqual(data, {'a': '1', 'b': ['x y', 'z'], 'c': {'d.e': 'q"uote\n'}, 'f': '0fbd77',
                                'g': '$(SRCROOT)/x', 'h': 'a.b-c_d/e'})

    def testRejectsBrokenFiles(self):
        for text in ('{ a = 1 }', '{ a = "open; }', '{ a = 1; } extra', '{ a = (1, 2; }'):
            with self.assertRaises((MODULE.FeatureError, IndexError), msg=text):
                MODULE.parse_openstep(text)


class InspectDirectoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def app(self):
        base = self.base
        write(base, 'Demo.xcodeproj/project.pbxproj', PROJECT)
        write(base, 'Config/App.xcconfig', '#include "Base.xcconfig"\nSWIFT_VERSION = 5.0;\n')
        write(base, 'Config/Base.xcconfig', 'SWIFT_OBJC_BRIDGING_HEADER = Demo/Bridge.h // the bridge\n'
                                            'SWIFT_VERSION[sdk=macosx*] = 6.0\n')
        write(base, 'Demo/Info.plist', plistlib.dumps({
            'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)', 'UILaunchScreen': {},
            'UISupportedInterfaceOrientations~ipad': ['UIInterfaceOrientationPortrait'],
            'UIBackgroundModes': ['audio'],
            'CFBundleURLTypes': [{'CFBundleURLSchemes': ['demo']}],
            'UIAppFonts': ['Demo.ttf'], 'UIUserInterfaceStyle': 'Dark'}))
        write(base, 'Demo/Demo.entitlements', plistlib.dumps({
            'aps-environment': 'development', 'com.apple.security.application-groups': ['group.demo'],
            'com.apple.developer.healthkit': True}))
        write(base, 'Widgets/Info.plist', plistlib.dumps(
            {'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'}}))
        write(base, 'Keys/Info.plist', plistlib.dumps(
            {'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.keyboard-service'}}))
        write(base, 'Demo/DemoApp.swift', APP)
        write(base, 'Demo/en.lproj/Localizable.strings', '"hello" = "Hello";\n')
        write(base, 'Demo/en.lproj/InfoPlist.strings', '"NSCameraUsageDescription" = "Scan";\n')
        write(base, 'Demo/Legacy.m', '#import <Foundation/Foundation.h>\n')
        write(base, 'Demo/Main.storyboard', '<document/>')
        write(base, 'Demo/LaunchScreen.storyboard', '<document/>')
        write(base, 'Settings.bundle/Root.plist', plistlib.dumps({}))
        write(base, 'Widgets/Widgets.swift', '@main\nstruct DemoWidgets: WidgetBundle { }\n')
        write(base, 'DemoTests/DemoTests.swift', '@main struct Runner: App { }\nlet d = UserDefaults.standard\n')
        write(base, 'Pods/Lib/Lib.swift', 'let d = UserDefaults.standard\n')
        write(base, 'Podfile', "platform :ios, '17.0'\npod 'Alamofire'\n  pod \"Charts\", '~> 4'\n")
        write(base, 'Package.swift', '// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(\n'
              '    name: "DemoKit",\n    products: [.library(name: "DemoKit", targets: ["DemoKit"])],\n'
              '    dependencies: [.package(url: "https://github.com/example/kit", from: "1.2.0")],\n'
              '    targets: [.target(name: "DemoKit")]\n)\n')
        return MODULE.inspect_directory(base)

    def testClassifiesAnOrdinaryApp(self):
        inspection = self.app()
        where = 'Demo.xcodeproj Demo'
        self.assertIn('Xcode project Demo.xcodeproj (Demo, Future, DemoWidgets, Keys, Clip, DemoCore)', inspection.found)
        self.assertIn('targets for other platforms skipped: DemoMac (macosx)', inspection.found)
        self.assertIn('Swift package DemoKit', inspection.found)
        self.assertIn('2 Swift file(s) checked', inspection.found)
        self.assertIsNone(inspection.whole)
        self.assertEqual(inspection.verdict(), 'some parts cannot come into JibunKit (see below); the rest can, with '
                         'the changes listed; some capabilities may not work with free signing')
        unsupported = MODULE.UNSUPPORTED
        self.assertEqual(places(inspection, unsupported, 'Needs iOS 27.0'), ['Demo.xcodeproj Future'])
        self.assertEqual(places(inspection, unsupported, 'Custom keyboard extension (com.apple.keyboard-service)'),
                         ['Demo.xcodeproj Keys'])
        self.assertEqual(places(inspection, unsupported, 'App Clip'), ['Demo.xcodeproj Clip'])
        self.assertEqual(places(inspection, unsupported, 'Settings.bundle'), ['Settings.bundle/Root.plist'])
        manual = MODULE.MANUAL
        self.assertEqual(places(inspection, manual, 'Widget extension'), ['Demo.xcodeproj DemoWidgets'])
        self.assertEqual(places(inspection, manual, 'Framework and library targets'), ['Demo.xcodeproj DemoCore'])
        self.assertEqual(places(inspection, manual, 'App Groups (group.demo)'), [where])
        self.assertEqual(places(inspection, manual, 'Fonts (UIAppFonts)'), [where])
        self.assertEqual(places(inspection, manual, 'bridging header'), [where])
        self.assertEqual(places(inspection, manual, 'outside the inspected directory (../Outside)'), ['Demo.xcodeproj'])
        self.assertEqual(places(inspection, manual, 'CocoaPods (Alamofire, Charts)'), ['Podfile'])
        self.assertEqual(places(inspection, manual, 'Objective-C, C or C++ code'), ['Demo/Legacy.m'])
        self.assertEqual(places(inspection, manual, 'Storyboards'), ['Demo/Main.storyboard'])
        self.assertEqual(places(inspection, manual, '[standard-defaults]'), ['Demo/DemoApp.swift:25'])
        self.assertEqual(places(inspection, manual, '[swiftdata-default-store]'), ['Demo/DemoApp.swift:8'])
        mechanical = MODULE.MECHANICAL
        self.assertEqual(places(inspection, mechanical, '[app-entry]'), ['Demo/DemoApp.swift:4'])
        self.assertEqual(places(inspection, mechanical, '[asset-lookup]'), ['Demo/DemoApp.swift:16'])
        self.assertEqual(places(inspection, mechanical, '[localized-text]'), ['Demo/DemoApp.swift:18'])
        self.assertEqual(places(inspection, mechanical, '[localized-string]'), ['Demo/DemoApp.swift:22'])
        self.assertEqual(places(inspection, mechanical, 'Swift 5 code'), [where])
        self.assertEqual(places(inspection, mechanical, 'UIUserInterfaceStyle'), [where])
        self.assertEqual(places(inspection, mechanical, 'Localized Info.plist text'), ['Demo/en.lproj/InfoPlist.strings'])
        self.assertIsNotNone(places(inspection, mechanical, 'Info.plist keys: copy them to `app.infoPlist` in '
                                    'JibunKitFeature.json: CFBundleURLTypes (demo), NSCameraUsageDescription, '
                                    'NSMicrophoneUsageDescription, UIBackgroundModes (audio).'))
        self.assertEqual(places(inspection, mechanical, 'Entitlements: copy them'), [where])
        self.assertIn('com.apple.developer.healthkit.', [m for (_, m) in inspection.items if 'Entitlements' in m][0])
        self.assertEqual(places(inspection, mechanical, 'No JibunKitFeature.json'), ['Package.swift'])
        self.assertEqual(places(inspection, MODULE.FREE_SIGNING, 'Push notifications (aps-environment)'), [where])
        brings = sorted(message for kind, message in inspection.items if kind == MODULE.BRINGS)
        self.assertIn('Swift package https://github.com/example/Kit.git (upToNextMajorVersion 1.2.0)', brings)
        self.assertIn('Swift package https://github.com/example/Exact (exactVersion 2.0.0)', brings)
        self.assertIn('Swift package local Packages/Core', brings)
        self.assertIn(f'{MODULE.UNPINNED}: https://github.com/example/Kit.git', brings)
        self.assertNotIn(f'{MODULE.UNPINNED}: https://github.com/example/Exact', brings)
        # The same package from the project and from Package.swift is listed once.
        self.assertEqual(len([m for m in brings if 'https://github.com/example/kit' in m.lower()]), 2)

    def testReportsNothingForTheMacOnlyMicrophoneAndTestCode(self):
        inspection = self.app()
        messages = ' '.join(message for _, message in inspection.items)
        self.assertNotIn('NSMotionUsageDescription', messages)
        self.assertNotIn('CFBundleIdentifier', messages)
        self.assertNotIn('UILaunchScreen', messages)
        self.assertNotIn('UISupportedInterfaceOrientations', messages)
        everywhere = [where for places in inspection.items.values() for where in places]
        self.assertFalse([where for where in everywhere if where.startswith(('DemoTests/', 'Pods/', 'Widgets/'))])
        self.assertNotIn('Demo/LaunchScreen.storyboard', everywhere)

    def testPrintsSectionsWithTheirPlaces(self):
        inspection = self.app()
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            MODULE.print_inspection(inspection)
        text = out.getvalue()
        self.assertTrue(text.startswith('Found: Xcode project Demo.xcodeproj'), text)
        self.assertIn('\nVerdict: some parts cannot come into JibunKit', text)
        order = [text.index(MODULE.SECTION_TITLES[section]) for section in
                 (MODULE.UNSUPPORTED, MODULE.MANUAL, MODULE.MECHANICAL, MODULE.FREE_SIGNING, MODULE.BRINGS)]
        self.assertEqual(order, sorted(order))
        self.assertIn('  [standard-defaults] ', text)
        self.assertIn('\n    Demo/DemoApp.swift:25\n', text)

    def testShortensLongListsOfPlaces(self):
        write(self.base, 'Package.swift', 'let package = Package(name: "A", products: [.library(name: "A", targets: ["A"])])')
        write(self.base, 'Sources/A/A.swift', 'let a = UserDefaults.standard\n' * 7)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            MODULE.print_inspection(MODULE.inspect_directory(self.base))
        self.assertIn('Sources/A/A.swift:5 (+2 more)\n', out.getvalue())

    def testAJibunKitFeatureCanBeAddedAsItIs(self):
        shutil.copytree(ROOT / 'Tuist/Templates', self.base / 'Tuist/Templates')
        module = MODULE.new(self.base, 'Notes', run_sync=False)
        inspection = MODULE.inspect_directory(module)
        self.assertTrue(inspection.feature)
        self.assertEqual(inspection.verdict(), 'a JibunKit Feature; it can be added as it is')
        self.assertEqual([section for section, _ in inspection.items if section != MODULE.BRINGS], [])
        (module / MODULE.MANIFEST).write_text('{"schema": 1}', encoding='utf-8')
        broken = MODULE.inspect_directory(module)
        self.assertIsNotNone(places(broken, MODULE.MANUAL, 'JibunKitFeature.json is not valid'))

    def testPackagesWithoutALibraryOrAnythingAtAll(self):
        write(self.base, 'Package.swift', 'let package = Package(name: "Tool", products: [.executable(name: "t", targets: ["T"])])')
        inspection = MODULE.inspect_directory(self.base)
        self.assertIsNotNone(places(inspection, MODULE.MANUAL, 'no library product'))
        empty = self.base / 'empty'
        write(empty, 'README.md', 'hello')
        self.assertEqual(MODULE.inspect_directory(empty).verdict(),
                         'not supported: no Swift code, Xcode project or Swift package was found')

    def testAProjectWithoutAnIOSApp(self):
        write(self.base, 'Mac.xcodeproj/project.pbxproj', '{ objects = { R = {isa = PBXProject; buildConfigurationList = L; '
              'targets = (T); }; L = {isa = XCConfigurationList; buildConfigurations = (C); }; C = {isa = '
              'XCBuildConfiguration; name = Release; buildSettings = {SDKROOT = macosx; }; }; T = {isa = '
              'PBXNativeTarget; name = Mac; productType = "com.apple.product-type.application"; '
              'buildConfigurationList = L; }; }; rootObject = R; }')
        inspection = MODULE.inspect_directory(self.base)
        self.assertEqual(inspection.whole, 'no iOS app target was found')
        self.assertIn('targets for other platforms skipped: Mac (macosx)', inspection.found)

    def testUnreadableProjectsAndOtherProjectTools(self):
        write(self.base, 'Broken.xcodeproj/project.pbxproj', '{ objects = ')
        write(self.base, 'App/App.swift', 'import SwiftUI\n')
        inspection = MODULE.inspect_directory(self.base)
        self.assertEqual(places(inspection, MODULE.NOT_READ, 'could not be read'), ['Broken.xcodeproj'])
        other = self.base / 'gen'
        write(other, 'project.yml', 'name: Demo\n')
        write(other, 'Sources/App.swift', '@main struct DemoApp: App { }\n')
        inspection = MODULE.inspect_directory(other)
        self.assertIsNotNone(places(inspection, MODULE.NOT_READ, 'XcodeGen'))
        self.assertEqual(places(inspection, MODULE.MECHANICAL, '[app-entry]'), ['Sources/App.swift:1'])

    def testSwiftPlaygroundsApp(self):
        write(self.base, 'Demo.swiftpm/Package.swift', 'let package = Package(name: "Demo", products: [\n'
              '    .iOSApplication(name: "Demo", targets: ["AppModule"],\n'
              '        capabilities: [.camera(purposeString: "Scan"), .microphone(purposeString: "Talk")])])\n')
        write(self.base, 'Demo.swiftpm/MyApp.swift', '@main struct MyApp: SwiftUI.App { }\n')
        inspection = MODULE.inspect_directory(self.base)
        self.assertEqual(places(inspection, MODULE.MECHANICAL, 'Swift Playgrounds app'), ['Demo.swiftpm/Package.swift'])
        self.assertIsNotNone(places(inspection, MODULE.MECHANICAL, 'Playgrounds app (camera, microphone)'))
        self.assertEqual(places(inspection, MODULE.MECHANICAL, '[app-entry]'), ['Demo.swiftpm/MyApp.swift:1'])
        self.assertEqual(inspection.verdict(), 'can be moved with mechanical changes only')


def git(cwd, *arguments):
    result = subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
                             '-c', 'core.autocrlf=false', *arguments], cwd=cwd, capture_output=True, check=True)
    return result.stdout.decode().strip()


class InspectRepositoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.upstream = Path(self.temporary.name) / 'upstream'
        write(self.upstream, 'Apps/Demo/Package.swift',
              'let package = Package(name: "Demo", products: [.library(name: "Demo", targets: ["Demo"])])')
        write(self.upstream, 'Apps/Demo/Sources/Demo/View.swift', 'let a = UserDefaults.standard\n')
        write(self.upstream, 'Apps/Demo/Sources/Demo/Logo.png', b'\x89PNG')
        git(self.upstream, 'init', '-q')
        git(self.upstream, 'add', '-A')
        # A submodule entry without a .gitmodules file is enough for the listing.
        git(self.upstream, 'update-index', '--add', '--cacheinfo', f'160000,{"1" * 40},Apps/Demo/Vendor')
        git(self.upstream, 'commit', '-q', '-m', 'app')
        self.commit = git(self.upstream, 'rev-parse', 'HEAD')

    def tearDown(self):
        self.temporary.cleanup()

    def testInspectsADirectoryOfACommitWithoutWritingAnything(self):
        host = Path(self.temporary.name) / 'host'
        host.mkdir()
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = MODULE.main(['--root', str(host), 'inspect', str(self.upstream), '--path', 'Apps/Demo'])
        self.assertEqual(status, 0, err.getvalue())
        text = out.getvalue()
        self.assertIn(f'Inspected {self.upstream.resolve()} Apps/Demo at {self.commit} (HEAD).\n', text)
        self.assertIn('Found: Swift package Demo; 1 Swift file(s) checked.\n', text)
        self.assertIn('Verdict: can be moved, with manual changes.\n', text)
        self.assertIn('Git submodules', text)
        self.assertIn('    Vendor\n', text)
        self.assertIn('    Sources/Demo/View.swift:1\n', text)
        self.assertEqual(list(host.iterdir()), [])

    def testAMissingDirectoryIsAnError(self):
        err = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
            status = MODULE.main(['--root', self.temporary.name, 'inspect', str(self.upstream), '--path', 'Nope'])
        self.assertEqual(status, 1)
        self.assertIn("no directory 'Nope'", err.getvalue())


if __name__ == '__main__':
    unittest.main()
