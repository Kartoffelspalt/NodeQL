import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "tool/sync_dev_after_merge.sh"


class SyncDevAfterMergeTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="nodeql-sync-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.remote = self.root / "remote.git"
        self.repo = self.root / "checkout"
        self.repo.mkdir()
        self.env = {
            **os.environ,
            "GIT_AUTHOR_NAME": "Sync test",
            "GIT_AUTHOR_EMAIL": "sync@example.invalid",
            "GIT_COMMITTER_NAME": "Sync test",
            "GIT_COMMITTER_EMAIL": "sync@example.invalid",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
        }
        self.git("init", "--bare", str(self.remote))
        # Reproduce the rule that rejected the original workflow's push.
        self.git(
            "--git-dir",
            str(self.remote),
            "config",
            "receive.denyNonFastForwards",
            "true",
        )
        self.git("init", "-b", "master")
        self.git("remote", "add", "origin", str(self.remote))
        self.commit("base", "base")
        self.git("checkout", "-b", "dev")
        self.dev = self.commit("feature", "release content")
        self.git("push", "origin", "master", "dev")
        self.git("checkout", "master")

    def git(self, *arguments, check=True):
        result = subprocess.run(
            ["git", *arguments],
            cwd=self.repo,
            env=self.env,
            capture_output=True,
            text=True,
        )
        if check and result.returncode:
            self.fail(f"git {arguments!r} failed:\n{result.stderr}")
        return result

    def rev(self, ref):
        return self.git("rev-parse", ref).stdout.strip()

    def remote_dev(self):
        return self.git("ls-remote", "origin", "refs/heads/dev").stdout.split()[0]

    def commit(self, message, content):
        (self.repo / "app.txt").write_text(content)
        self.git("add", "app.txt")
        self.git("commit", "-m", message)
        return self.rev("HEAD")

    def release(self, method="squash"):
        if method == "squash":
            self.git("merge", "--squash", "dev")
            self.git("commit", "-m", "Squashed release")
        elif method == "rebase":
            self.git("cherry-pick", "--no-commit", self.dev)
            self.git("commit", "-m", "Rebased release")
        else:
            self.git("merge", "--no-ff", "dev", "-m", "Merged release")
        self.merge = self.rev("HEAD")
        self.git("push", "origin", "master")
        self.git("fetch", "origin")

    def sync(self, **overrides):
        return subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=self.repo,
            env={
                **self.env,
                "MERGED_DEV_SHA": self.dev,
                "MERGE_SHA": self.merge,
                **overrides,
            },
            capture_output=True,
            text=True,
        )

    def assert_synced(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.git("fetch", "origin")
        synced = self.remote_dev()
        self.assertEqual(self.rev(f"{synced}^{{tree}}"), self.rev("master^{tree}"))
        self.git("merge-base", "--is-ancestor", self.dev, synced)
        self.git("merge-base", "--is-ancestor", self.rev("master"), synced)
        return synced

    def test_squash_sync_passes_with_non_fast_forward_updates_blocked(self):
        self.release()
        rejected = self.git(
            "push",
            f"--force-with-lease=refs/heads/dev:{self.dev}",
            "origin",
            f"{self.merge}:refs/heads/dev",
            check=False,
        )
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual(self.remote_dev(), self.dev)

        synced = self.assert_synced(self.sync())
        self.assertEqual(self.rev(f"{synced}^1"), self.dev)
        self.assertEqual(self.rev(f"{synced}^2"), self.merge)

    def test_rebase_sync_preserves_both_histories(self):
        self.release("rebase")
        self.assertNotEqual(self.merge, self.dev)
        self.assert_synced(self.sync())

    def test_regular_merge_advances_directly_to_master(self):
        self.release("merge")
        self.assertEqual(self.assert_synced(self.sync()), self.merge)

    def test_sync_includes_master_changes_after_release_merge(self):
        self.release()
        self.commit("Later master fix", "release content with later fix")
        self.git("push", "origin", "master")
        self.assert_synced(self.sync())

    def test_skips_when_dev_has_new_work(self):
        self.release()
        self.git("checkout", "dev")
        new_dev = self.commit("New development", "unreleased content")
        self.git("push", "origin", "dev")
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Skipping the sync", result.stdout)
        self.assertEqual(self.remote_dev(), new_dev)

    def test_skips_when_dev_was_deleted(self):
        self.release()
        self.git("push", "origin", "--delete", "dev")
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Skipping the sync", result.stdout)
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/dev").stdout, "")

    def test_rejects_merge_commit_not_in_master(self):
        self.release()
        result = self.sync(MERGE_SHA=self.dev)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no longer in master", result.stdout)
        self.assertEqual(self.remote_dev(), self.dev)

    def test_rerun_does_not_create_another_sync_commit(self):
        self.release()
        synced = self.assert_synced(self.sync())
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remote_dev(), synced)

    def test_concurrent_push_is_not_overwritten(self):
        self.release()
        self.git("checkout", "dev")
        new_dev = self.commit("Concurrent development", "new content")
        self.git("push", "origin", "dev")
        self.git("update-ref", "refs/remotes/origin/dev", self.dev)
        result = self.sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.remote_dev(), new_dev)

    def test_concurrent_deletion_does_not_recreate_dev(self):
        self.release()
        self.git("push", "origin", "--delete", "dev")
        self.git("update-ref", "refs/remotes/origin/dev", self.dev)
        result = self.sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/dev").stdout, "")


if __name__ == "__main__":
    unittest.main()
