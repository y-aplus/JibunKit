from datetime import datetime, timezone
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("build_ipa", ROOT / "Tools/build-ipa.py")
build_ipa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_ipa)


class ParseRepoTests(unittest.TestCase):
    def test_https_ssh_and_token_forms(self):
        for url in ["https://github.com/owner/host.git", "https://github.com/owner/host",
                    "https://x-access-token:abc@github.com/owner/host.git\n",
                    "git@github.com:owner/host.git", "ssh://git@github.com/owner/host.git"]:
            self.assertEqual(build_ipa.parse_repo(url), "owner/host", url)

    def test_rejects_other_hosts(self):
        with self.assertRaisesRegex(build_ipa.Failure, "not a GitHub repository"):
            build_ipa.parse_repo("https://gitlab.com/owner/host.git")


class PickRunTests(unittest.TestCase):
    since = datetime(2026, 10, 11, 7, 0, tzinfo=timezone.utc)

    def test_picks_the_newest_run_of_the_commit_after_dispatch(self):
        runs = [
            {"databaseId": 1, "headSha": "abc", "createdAt": "2026-10-11T06:59:00Z"},
            {"databaseId": 2, "headSha": "abc", "createdAt": "2026-10-11T07:00:05Z"},
            {"databaseId": 3, "headSha": "def", "createdAt": "2026-10-11T07:00:06Z"},
            {"databaseId": 4, "headSha": "abc", "createdAt": "2026-10-11T07:00:09Z"},
        ]
        self.assertEqual(build_ipa.pick_run(runs, "abc", self.since), 4)

    def test_none_before_the_run_appears(self):
        runs = [{"databaseId": 1, "headSha": "abc", "createdAt": "2026-10-11T06:00:00Z"}]
        self.assertIsNone(build_ipa.pick_run(runs, "abc", self.since))


if __name__ == "__main__":
    unittest.main()
