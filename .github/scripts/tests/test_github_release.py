import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "github_release.py"
spec = importlib.util.spec_from_file_location("github_release", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
SOURCE = "e6d9a5608d63012c30345edecaf8b8de1db05130"
PREVIOUS = "07702dea844d165b2f1a8116084ef6d190224a4c"


class FakeGitHub:
    """Remote state; commands never execute gh or contact the network."""

    def __init__(self, target=None, release=False, assets=None):
        self.target = target
        self.release = {"id": 7, "draft": False, "target_commitish": "main"} if release else None
        self.assets = dict(assets or {})
        self.annotated = False
        self.create_race_sha = None
        self.commands = []

    def get(self, endpoint, *, missing_ok=False):
        if endpoint.startswith("releases/tags/"):
            return self.release
        if endpoint.startswith("git/ref/tags/"):
            if not self.target:
                return None
            return {"object": {"type": "tag" if self.annotated else "commit", "sha": self.target}}
        if endpoint.startswith("git/tags/"):
            return {"object": {"type": "commit", "sha": self.target}}
        if endpoint.startswith("releases/7/assets?"):
            page = int(endpoint.rsplit("=", 1)[1])
            return [{"name": name} for name in self.assets][(page - 1) * 100:page * 100]
        raise AssertionError(endpoint)

    def command(self, *args):
        self.commands.append(args)
        if args[0] == "create":
            self.release = {"id": 7, "draft": False}
            self.target = self.create_race_sha or args[args.index("--target") + 1]
            if self.create_race_sha:
                raise subprocess.CalledProcessError(1, ["gh", "release", *args])
        elif args[0] == "upload":
            for name in args[2:]:
                if name in self.assets:
                    raise AssertionError("Attempt to overwrite an existing asset")
                self.assets[name] = Path(name).read_bytes()
        elif args[0] == "download":
            name = args[args.index("--pattern") + 1]
            directory = args[args.index("--dir") + 1]
            Path(directory, name).write_bytes(self.assets[name])
        else:
            raise AssertionError(args)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.original_cwd = Path.cwd()
        os.chdir(self.temp.name)
        self.github = FakeGitHub()
        self.release = module.Release(self.github, SOURCE, "1.4.4+535")
        self.apk_bytes = b"signed APK for the exact source commit"
        self.checksum = f"{hashlib.sha256(self.apk_bytes).hexdigest()}  {self.release.apk}\n".encode()
        Path(self.release.apk).write_bytes(self.apk_bytes)
        Path(self.release.names[1]).write_bytes(self.checksum)

    def tearDown(self):
        os.chdir(self.original_cwd)
        self.temp.cleanup()

    def existing(self, assets):
        self.github.target = SOURCE
        self.github.release = {"id": 7, "draft": False, "target_commitish": "main"}
        self.github.assets = assets

    def uploads(self):
        return [args for args in self.github.commands if args[0] == "upload"]

    def test_new_version_creates_release_at_exact_source_and_uploads_pair(self):
        self.assertTrue(self.release.needs_build())
        self.assertEqual(self.github.commands, [])
        self.release.publish()
        self.assertEqual(self.github.target, SOURCE)
        self.assertEqual(self.github.commands[0][0], "create")
        self.assertEqual(self.uploads(), [("upload", self.release.tag, *self.release.names)])

    def test_existing_aab_release_is_completed_without_changing_it(self):
        self.existing({"app-release.aab": b"published Play bundle"})
        metadata = self.github.release.copy()
        self.assertTrue(self.release.needs_build())
        self.release.publish()
        self.assertEqual(self.github.assets["app-release.aab"], b"published Play bundle")
        self.assertEqual(self.github.release, metadata)
        self.assertFalse(any(args[0] == "create" for args in self.github.commands))
        self.assertEqual(self.uploads(), [("upload", self.release.tag, *self.release.names)])

    def test_complete_release_skips_build_and_does_not_replace_assets(self):
        self.existing(dict(zip(self.release.names, [self.apk_bytes, self.checksum])))
        self.assertFalse(self.release.needs_build())
        self.release.publish()
        self.assertEqual(self.github.commands, [])

    def test_other_commit_cannot_reuse_a_version(self):
        self.existing({"app-release.aab": b"old"})
        self.github.target = PREVIOUS
        for operation in (self.release.needs_build, self.release.publish):
            with self.assertRaisesRegex(module.ReleaseError, "no apunta al commit"):
                operation()
        self.assertEqual(self.github.commands, [])

    def test_original_534_collision_remains_blocked(self):
        self.github.target = PREVIOUS
        self.github.release = {"id": 7}
        release = module.Release(self.github, SOURCE, "1.4.3+534")
        with self.assertRaisesRegex(module.ReleaseError, "Incrementa la version"):
            release.needs_build()

    def test_annotated_tag_is_resolved_to_its_commit(self):
        self.github.target = SOURCE
        self.github.annotated = True
        self.assertTrue(self.release.needs_build())
        self.github.target = PREVIOUS
        with self.assertRaises(module.ReleaseError):
            self.release.needs_build()

    def test_matching_tag_without_release_can_be_published(self):
        self.github.target = SOURCE
        self.release.publish()
        self.assertEqual(self.github.target, SOURCE)
        self.assertEqual(set(self.github.assets), set(self.release.names))

    def test_release_without_verifiable_tag_is_rejected(self):
        self.github.release = {"id": 7}
        with self.assertRaisesRegex(module.ReleaseError, "tag verificable"):
            self.release.needs_build()

    def test_draft_is_not_published_implicitly(self):
        self.existing({})
        self.github.release["draft"] = True
        with self.assertRaisesRegex(module.ReleaseError, "borrador"):
            self.release.publish()
        self.assertEqual(self.github.commands, [])

    def test_complete_assets_after_first_page_still_skip_build(self):
        self.existing({f"other-{i}": b"asset" for i in range(101)})
        self.github.assets.update(zip(self.release.names, [self.apk_bytes, self.checksum]))
        self.assertFalse(self.release.needs_build())

    def test_partial_apk_upload_is_completed_only_if_bytes_match(self):
        self.existing({self.release.apk: self.apk_bytes})
        self.release.publish()
        self.assertEqual(self.uploads(), [("upload", self.release.tag, self.release.names[1])])

    def test_partial_checksum_upload_is_completed_only_if_bytes_match(self):
        self.existing({self.release.names[1]: self.checksum})
        self.release.publish()
        self.assertEqual(self.uploads(), [("upload", self.release.tag, self.release.apk)])

    def test_mismatched_partial_assets_cannot_be_mixed_or_overwritten(self):
        for name in self.release.names:
            with self.subTest(name=name):
                self.existing({name: b"different artifact", "app-release.aab": b"preserved"})
                with self.assertRaisesRegex(module.ReleaseError, "no se sobrescribe"):
                    self.release.publish()
                self.assertEqual(self.uploads(), [])
                self.assertEqual(self.github.assets["app-release.aab"], b"preserved")

    def test_release_created_during_build_is_reused(self):
        self.assertTrue(self.release.needs_build())
        self.existing({"app-release.aab": b"concurrent bundle"})
        self.release.publish()
        self.assertEqual(self.github.commands[0][0], "upload")

    def test_release_creation_race_is_recovered_for_same_commit(self):
        self.github.create_race_sha = SOURCE
        self.release.publish()
        self.assertEqual(set(self.github.assets), set(self.release.names))

    def test_release_creation_race_with_other_commit_is_rejected(self):
        self.github.create_race_sha = PREVIOUS
        with self.assertRaises(module.ReleaseError):
            self.release.publish()
        self.assertEqual(self.uploads(), [])

    def test_tag_changed_after_preflight_blocks_upload(self):
        self.existing({})
        self.assertTrue(self.release.needs_build())
        self.github.target = PREVIOUS
        with self.assertRaises(module.ReleaseError):
            self.release.publish()
        self.assertEqual(self.github.commands, [])

    def test_wrong_local_checksum_blocks_all_remote_writes(self):
        Path(self.release.names[1]).write_text("incorrect\n")
        with self.assertRaisesRegex(module.ReleaseError, "checksum local"):
            self.release.publish()
        self.assertEqual(self.github.commands, [])

    def test_invalid_source_or_version_is_rejected(self):
        for source, version in [("main", "1.4.4+535"), (SOURCE, "1.4.4"), (SOURCE, "1.4.4+0")]:
            with self.subTest(source=source, version=version), self.assertRaises(module.ReleaseError):
                module.Release(self.github, source, version)

    def test_check_exports_checkout_sha_and_build_decision(self):
        Path("pubspec.yaml").write_text("name: nocknock\nversion: 1.4.4+535\n")
        env = {"GITHUB_REPOSITORY": "nicoGG/knocknock-front", "GITHUB_OUTPUT": "output", "GITHUB_ENV": "env"}
        with patch.dict(os.environ, env), patch.object(module.sys, "argv", ["script", "check"]), \
                patch.object(module, "GitHub", return_value=self.github), \
                patch.object(module.subprocess, "check_output", return_value=SOURCE + "\n"):
            module.main()
        self.assertEqual(Path("output").read_text(), "needs_build=true\n")
        self.assertIn(f"SOURCE_SHA={SOURCE}\n", Path("env").read_text())
        self.assertIn("RELEASE_TAG=v1.4.4-build-535\n", Path("env").read_text())
        self.assertEqual(self.github.commands, [])


class ApiTests(unittest.TestCase):
    def response(self, status, code=0, body='{"id": 7}'):
        return subprocess.CompletedProcess([], code, f"HTTP/2.0 {status} response\nX-Header: value\n\n{body}", "")

    def test_reads_api_json(self):
        with patch.object(module.subprocess, "run", return_value=self.response(200)):
            self.assertEqual(module.GitHub("owner/repo").get("releases/7"), {"id": 7})

    def test_only_404_is_treated_as_absent(self):
        with patch.object(module.subprocess, "run", return_value=self.response(404, 1)):
            github = module.GitHub("owner/repo")
            self.assertIsNone(github.get("release", missing_ok=True))
            with self.assertRaises(module.ReleaseError):
                github.get("release")

    def test_auth_rate_limit_server_and_network_errors_fail_closed(self):
        failures = [self.response(status, 1) for status in (401, 403, 429, 500)]
        failures.append(subprocess.CompletedProcess([], 1, "", "network failure"))
        for response in failures:
            with self.subTest(response=response), patch.object(module.subprocess, "run", return_value=response):
                with self.assertRaises(module.ReleaseError):
                    module.GitHub("owner/repo").get("release", missing_ok=True)


if __name__ == "__main__":
    unittest.main()
