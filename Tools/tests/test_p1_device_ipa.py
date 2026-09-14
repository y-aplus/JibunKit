import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile


SPEC = importlib.util.spec_from_file_location("p1_ipa", Path(__file__).resolve().parents[1] / "verify-p1-device-ipa.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class P1DeviceInventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ipa = Path(self.temp.name) / "candidate.ipa"
        self.entries = {}
        self.widget = "Payload/JibunKit.app/PlugIns/JibunKitWidget_Extension.appex/"
        for prefix, suffix in [("Payload/JibunKit.app/", ""), (self.widget, ".Widget"),
                               ("Payload/JibunKit.app/PlugIns/JibunKitShare_Extension.appex/", ".Share")]:
            self.entries[prefix + "Info.plist"] = plistlib.dumps({"CFBundleIdentifier": "com.jibunkit.app" + suffix,
                "CFBundleShortVersionString": "0.7.1", "CFBundleVersion": "9", "CFBundleExecutable": "main"})
            self.entries[prefix + "main"] = b"binary"
        self.entries[self.widget + "main"] = b"JibunKitCounterWidget\0com.jibunkit.fixture.feature-a.widget\0com.jibunkit.fixture.feature-b.widget"
        for owner in "AB":
            for name in ["Info.plist", "en.lproj/Localizable.strings", "ja.lproj/Localizable.strings"]:
                self.entries[self.widget + "JibunKit_P1WidgetFeature" + owner + ".bundle/" + name] = b"resource"

    def write(self):
        with zipfile.ZipFile(self.ipa, "w") as archive:
            for name, data in self.entries.items():
                archive.writestr(name, data)

    def testCompleteCandidateRecordsInventoryWithoutClaimingGallery(self):
        self.write()
        report = MODULE.inspect(self.ipa, "0.7.1", "9")
        self.assertEqual(len(report["widget_kinds"]), 3)
        self.assertIn("requires separate evidence", report["scope"])

    def testCounterOnlyExportCannotPassUsingHostResourceCopies(self):
        self.entries[self.widget + "main"] = b"JibunKitCounterWidget"
        self.write()
        with self.assertRaisesRegex(ValueError, "Missing Widget kind"):
            MODULE.inspect(self.ipa, "0.7.1", "9")

    def testResourceOnlyInAppDoesNotSatisfyWidgetResource(self):
        name = self.widget + "JibunKit_P1WidgetFeatureA.bundle/ja.lproj/Localizable.strings"
        self.entries["Payload/JibunKit.app/JibunKit_P1WidgetFeatureA.bundle/ja.lproj/Localizable.strings"] = self.entries.pop(name)
        self.write()
        with self.assertRaisesRegex(ValueError, "Missing exported Widget resource"):
            MODULE.inspect(self.ipa, "0.7.1", "9")

    def testWrongVersionOrReplacedExtensionFails(self):
        self.write()
        with self.assertRaisesRegex(ValueError, "identity/version"):
            MODULE.inspect(self.ipa, "0.8.0", "9")
        info = self.widget + "Info.plist"
        metadata = plistlib.loads(self.entries[info])
        metadata["CFBundleIdentifier"] = "com.example.other"
        self.entries[info] = plistlib.dumps(metadata)
        self.write()
        with self.assertRaisesRegex(ValueError, "identity/version"):
            MODULE.inspect(self.ipa, "0.7.1", "9")
