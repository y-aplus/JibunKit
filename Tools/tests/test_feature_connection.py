import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("connection", Path(__file__).parents[1] / "check-feature-connection.py")
connection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(connection)


class FeatureConnectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.module = self.root / "Modules/Notes"
        self.project = {"packages": [{"local": {"path": {"type": "relativeToManifest", "pathString": "Modules/Notes"}}}],
                        "targets": [{"name": "JibunKit-App", "dependencies": [{"package": {"product": "NotesFeature"}}]},
                                    {"name": "Widget", "dependencies": []}]}
        self.package = {"products": [{"name": "NotesFeature", "type": {"library": ["automatic"]}, "targets": ["NotesFeature"]}],
                        "targets": [{"name": "NotesFeature", "type": "regular"}]}

    def check(self):
        return connection.inspect(self.project, self.package, self.root, self.module, "NotesFeature", "JibunKit-App")

    def test_complete_connection_does_not_claim_registry_or_build(self):
        original = copy.deepcopy(self.project)
        self.assertIn("does not prove compilation or Registry", self.check())
        self.assertEqual(self.project, original)

    def test_missing_path_points_to_project_packages(self):
        self.project["packages"] = []
        with self.assertRaisesRegex(connection.ConnectionError, "Package path missing"):
            self.check()

    def test_product_typo_points_to_package_products(self):
        self.package["products"][0]["name"] = "NoteFeature"
        with self.assertRaisesRegex(connection.ConnectionError, "Library product.*missing"):
            self.check()

    def test_missing_library_target_is_rejected(self):
        self.package["targets"] = []
        with self.assertRaisesRegex(connection.ConnectionError, "missing target NotesFeature"):
            self.check()

    def test_executable_is_not_an_embeddable_library(self):
        self.package["products"][0]["type"] = {"executable": None}
        with self.assertRaisesRegex(connection.ConnectionError, "not a library product"):
            self.check()

    def test_dependency_on_wrong_host_does_not_pass(self):
        self.project["targets"][1]["dependencies"] = self.project["targets"][0]["dependencies"]
        self.project["targets"][0]["dependencies"] = []
        with self.assertRaisesRegex(connection.ConnectionError, "Host dependency missing"):
            self.check()

    def test_missing_host_is_distinct_from_missing_dependency(self):
        self.project["targets"][0]["name"] = "OtherApp"
        with self.assertRaisesRegex(connection.ConnectionError, "Host target.*missing"):
            self.check()

    def test_root_and_file_relative_paths_resolve_natively(self):
        (self.root / "Tuist").mkdir()
        path = self.project["packages"][0]["local"]["path"]
        path["type"] = "relativeToRoot"
        self.assertIn("passed", self.check())
        path.update(type="relativeToCurrentFile", callerPath=str(self.root / "Tuist/Helper.swift"), pathString="../Modules/Notes")
        self.assertIn("passed", self.check())

    def test_unknown_dump_shape_fails_closed(self):
        self.project["packages"][0] = {"futureKind": "Modules/Notes"}
        with self.assertRaisesRegex(connection.ConnectionError, "Unsupported Tuist package kind"):
            self.check()


if __name__ == "__main__":
    unittest.main()
