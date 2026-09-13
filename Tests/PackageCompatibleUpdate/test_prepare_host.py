import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[2]
TOOL = REPOSITORY / "Tools/prepare-package-compatible-update-host.py"
A_SOURCE = Path("Tests/PackageResources/FeatureA/Sources/ResourceFeatureA/FeatureAStoredValue.swift")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class PrepareCompatibleUpdateHostTests(unittest.TestCase):
    def host(self, root: Path) -> Path:
        host = root / "GeneratedHost"
        (host / "Sources/JibunKit").mkdir(parents=True)
        (host / "Package.swift").write_text("// generated host\n", encoding="utf-8")
        (host / "Project.swift").write_text(
            "// ResourceFeatureA ResourceFeatureB\n", encoding="utf-8"
        )
        (host / "Sources/JibunKit/MiniAppRegistry.swift").write_text(
            "// P0CCompatibleUpdateProbe.definition\n", encoding="utf-8"
        )
        return host

    def run_tool(self, host: Path, stage: str, succeeds: bool = True) -> subprocess.CompletedProcess:
        result = subprocess.run(
            [sys.executable, str(TOOL), "--host", str(host), "--stage", stage],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(result.returncode == 0, succeeds, result.stdout + result.stderr)
        return result

    def test_v2_changes_only_prepared_feature_a_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            host = self.host(Path(temporary))
            self.run_tool(host, "v1")
            before = {
                path.relative_to(host): digest(path)
                for path in host.rglob("*") if path.is_file()
            }
            self.run_tool(host, "v2")
            after = {
                path.relative_to(host): digest(path)
                for path in host.rglob("*") if path.is_file()
            }
            changed = {path for path in before if before[path] != after[path]}
            self.assertEqual(changed, {A_SOURCE})
            self.assertEqual(set(before), set(after))

    def test_v2_rejects_changed_feature_b(self):
        with tempfile.TemporaryDirectory() as temporary:
            host = self.host(Path(temporary))
            self.run_tool(host, "v1")
            b_resource = host / "Tests/PackageResources/FeatureB/Sources/ResourceFeatureB/Resources/shared.json"
            b_resource.write_text('{"owner":"changed"}\n', encoding="utf-8")
            result = self.run_tool(host, "v2", succeeds=False)
            self.assertIn("non-A host inputs changed", result.stderr)


if __name__ == "__main__":
    unittest.main()
