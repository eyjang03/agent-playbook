"""Real local Git repositories; no GitHub, account changes, or production files."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import local_state
import playbook
import project


class ProjectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="playbook-project-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.state = self.root / "state"
        self.env = patch.dict(os.environ, {
            "AGENT_PLAYBOOK_HOME": str(self.state), "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull, "GIT_AUTHOR_NAME": "Test",
            "GIT_AUTHOR_EMAIL": "test@example.invalid", "GIT_COMMITTER_NAME": "Test",
            "GIT_COMMITTER_EMAIL": "test@example.invalid"})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.remote = self.root / "remote.git"
        self.a = self.root / "computer-a"
        self.b = self.root / "computer-b"
        self.git(self.root, "init", "-q", "--bare", "-b", "trunk", str(self.remote))
        self.git(self.root, "init", "-q", "-b", "trunk", str(self.a))
        self.git(self.a, "remote", "add", "origin", str(self.remote))
        self.commit(self.a, "README.md", "first\n")
        self.git(self.a, "push", "-q", "-u", "origin", "trunk")
        self.git(self.root, "clone", "-q", str(self.remote), str(self.b))

    def git(self, repo, *args):
        return subprocess.run(["git", "-C", str(repo), *args], check=True,
                              capture_output=True, text=True).stdout.strip()

    def commit(self, repo, name, body):
        p = Path(repo, name)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body)
        self.git(repo, "add", "--", name)
        self.git(repo, "commit", "-qm", "test change")

    def rev(self, repo):
        return self.git(repo, "rev-parse", "HEAD")

    def enable(self, repo=None, download=False, mode="auto"):
        return project.configure(str(repo or self.a), mode, "origin", "trunk", download)

    def run_sync(self, phase="start", repo=None, app="codex"):
        return project.run(phase, str(repo or self.a), app)

    def test_unselected_and_cloned_projects_have_no_network(self):
        self.enable()
        (self.b / ".project-sync").touch()
        with patch.object(project, "synchronize", side_effect=AssertionError("network")):
            self.assertEqual(self.run_sync(repo=self.b), "")
        self.assertIsNone(project.load_policy(str(self.b)))

    def test_local_and_ask_modes_do_not_contact_remotes(self):
        for mode in ("local", "ask"):
            self.enable(mode=mode)
            with patch.object(project, "synchronize", side_effect=AssertionError("network")):
                self.assertIn("no network", self.run_sync())
                self.assertEqual(self.run_sync("end"), "")

    def test_configuration_is_local_and_rejects_parent_scope(self):
        before = self.rev(self.remote)
        self.enable()
        self.assertEqual(self.rev(self.remote), before)
        nested = self.a / "selected child"
        nested.mkdir()
        with self.assertRaises(project.Blocked):
            project.configure(str(nested), "local")
        self.assertEqual(project.inspect(str(nested))["git_root"], str(self.a))
        empty = self.root / "not a repo"
        empty.mkdir()
        self.assertIsNone(project.inspect(str(empty))["git_root"])

    def test_two_computers_upload_and_download_then_read_fresh_handoff(self):
        self.enable(download=True)
        self.commit(self.b, "HANDOFF.md", "Received the new handoff.\n")
        self.git(self.b, "push", "-q")
        out = playbook.start("codex", "context", str(self.a))
        text = out["hookSpecificOutput"]["additionalContext"]
        self.assertIn("Downloaded 1", text)
        self.assertIn("Received the new handoff", text)
        self.assertEqual(self.rev(self.a), self.rev(self.b))
        self.commit(self.a, "work.txt", "finished\n")
        self.assertIn("Uploaded 1", self.run_sync("end", app="claude"))
        self.assertEqual(self.rev(self.remote), self.rev(self.a))
        records = local_state.read("project-status.json")[str(self.a)]
        self.assertEqual(records["codex"]["start"]["outcome"], "ok")
        self.assertEqual(records["claude"]["end"]["outcome"], "ok")

    def test_download_requires_separate_choice(self):
        self.enable(download=False)
        self.commit(self.b, "new.txt", "remote\n")
        self.git(self.b, "push", "-q")
        before = self.rev(self.a)
        self.assertIn("Download is pending", self.run_sync())
        self.assertEqual(self.rev(self.a), before)

    def test_split_history_is_preserved(self):
        self.enable(download=True)
        self.commit(self.a, "a.txt", "local\n")
        self.commit(self.b, "b.txt", "remote\n")
        self.git(self.b, "push", "-q")
        before = self.rev(self.a)
        self.assertIn("split", self.run_sync())
        self.assertEqual(self.rev(self.a), before)
        self.assertEqual(self.rev(self.remote), self.rev(self.b))

    def test_changed_remote_wrong_branch_detached_and_replaced_checkout_block(self):
        self.enable()
        self.git(self.a, "remote", "set-url", "origin", str(self.b))
        self.assertIn("remote changed", self.run_sync())
        self.git(self.a, "remote", "set-url", "origin", str(self.remote))
        self.git(self.a, "checkout", "-qb", "other")
        self.assertIn("another branch", self.run_sync())
        self.git(self.a, "checkout", "-q", "--detach")
        self.assertIn("detached", self.run_sync())
        self.git(self.a, "checkout", "-q", "trunk")
        self.a.rename(self.root / "old-checkout")
        self.git(self.root, "clone", "-q", str(self.remote), str(self.a))
        self.assertIn("checkout changed", self.run_sync())

    def test_credential_url_and_multiple_push_destinations_rejected(self):
        self.git(self.a, "remote", "set-url", "origin", "https://username:fake-password@example.invalid/repo")
        with self.assertRaises(project.Blocked):
            self.enable()
        self.assertNotIn("fake-password", json.dumps(project.inspect(str(self.a))))
        self.git(self.a, "remote", "set-url", "origin", str(self.remote))
        self.git(self.a, "remote", "set-url", "--add", "--push", "origin", str(self.remote))
        self.git(self.a, "remote", "set-url", "--add", "--push", "origin", str(self.b))
        with self.assertRaises(project.Blocked):
            self.enable()

    def test_legacy_marker_does_not_enable_second_sync(self):
        (self.a / ".project-sync").touch()
        with self.assertRaises(project.Blocked):
            self.enable()
        self.enable(mode="ask")
        self.assertIn("no network", self.run_sync())

    def test_linked_worktree_stays_unenrolled(self):
        self.enable()
        task = self.root / "task-worktree"
        self.git(self.a, "worktree", "add", "-qb", "task", str(task))
        with self.assertRaises(project.Blocked):
            self.enable(repo=task)
        self.assertEqual(self.run_sync(repo=task), "")

    def test_unfinished_git_operation_blocks(self):
        self.enable()
        (self.a / ".git" / "MERGE_HEAD").write_text(self.rev(self.b))
        self.assertIn("operation is in progress", self.run_sync())

    def test_shallow_clone_cannot_enable_auto(self):
        shallow = self.root / "shallow"
        self.git(self.root, "clone", "-q", "--depth=1", self.remote.as_uri(), str(shallow))
        with self.assertRaises(project.Blocked):
            self.enable(repo=shallow)

    def test_missing_remote_branch_and_offline_do_not_use_stale_refs(self):
        self.enable()
        self.assertIn("In sync", self.run_sync())
        self.git(self.remote, "update-ref", "-d", "refs/heads/trunk")
        self.commit(self.a, "a.txt", "new\n")
        self.assertIn("Tell the user", self.run_sync("end"))
        self.assertEqual(project.optional_git(str(self.remote), "rev-parse", "--verify", "refs/heads/trunk"), "")
        self.remote.rename(self.root / "offline.git")
        self.assertIn("Tell the user", self.run_sync())

    def test_secret_added_then_removed_still_blocks_upload(self):
        self.enable()
        before = self.rev(self.remote)
        fake = "AKIA" + "Z" * 16
        self.commit(self.a, "config.txt", fake + "\n")
        self.commit(self.a, "config.txt", "removed\n")
        self.assertIn("credential", self.run_sync("end"))
        self.assertEqual(self.rev(self.remote), before)

    def test_secret_filename_blocks_first_upload_scan(self):
        self.commit(self.a, ".env", "PASSWORD=private\n")
        with self.assertRaises(project.Blocked):
            project.secret_scan(str(self.a), None, self.rev(self.a))

    def test_dirty_tracked_untracked_and_ignored_paths_survive(self):
        self.enable(download=True)
        (self.a / "README.md").write_text("unfinished\n")
        self.commit(self.b, "README.md", "incoming\n")
        self.git(self.b, "push", "-q")
        self.assertIn("uncommitted", self.run_sync())
        self.assertEqual((self.a / "README.md").read_text(), "unfinished\n")
        self.git(self.a, "restore", "README.md")
        (self.a / "private.txt").write_text("unsaved\n")
        self.assertIn("untracked", self.run_sync())
        self.assertEqual((self.a / "private.txt").read_text(), "unsaved\n")
        (self.a / ".git" / "info" / "exclude").write_text("private.txt\nignored.txt\n")
        (self.a / "ignored.txt").write_text("ignored work\n")
        self.commit(self.b, "ignored.txt", "incoming ignored\n")
        self.git(self.b, "push", "-q")
        self.assertIn("ignored", self.run_sync())
        self.assertEqual((self.a / "ignored.txt").read_text(), "ignored work\n")

    def test_directory_replacement_and_symlink_ancestor_do_not_lose_files(self):
        self.enable(download=True)
        (self.a / ".git" / "info" / "exclude").write_text("folder/\n")
        (self.a / "folder").mkdir()
        (self.a / "folder" / "private").write_text("keep\n")
        self.commit(self.b, "folder", "remote file\n")
        self.git(self.b, "push", "-q")
        self.assertIn("ignored", self.run_sync())
        self.assertEqual((self.a / "folder" / "private").read_text(), "keep\n")
        outside = self.root / "outside"
        outside.mkdir()
        (self.a / "link").symlink_to(outside, target_is_directory=True)
        self.commit(self.b, "link/child", "incoming\n")
        self.git(self.b, "push", "-q")
        self.assertIn("Tell the user", self.run_sync())
        self.assertFalse((outside / "child").exists())

    def test_remote_advances_during_scan_push_is_rejected(self):
        self.enable()
        self.commit(self.a, "a.txt", "local\n")
        before = self.rev(self.a)
        def concurrent_push(*args):
            self.commit(self.b, "b.txt", "remote\n")
            self.git(self.b, "push", "-q")
        with patch.object(project, "secret_scan", side_effect=concurrent_push):
            self.assertIn("Tell the user", self.run_sync("end"))
        self.assertEqual(self.rev(self.remote), self.rev(self.b))
        self.assertEqual(self.rev(self.a), before)

    def test_exact_branch_upload_does_not_push_tags_or_other_branches(self):
        self.enable()
        self.commit(self.a, "a.txt", "local\n")
        self.git(self.a, "tag", "-am", "tag", "do-not-upload")
        self.git(self.a, "config", "push.followTags", "true")
        self.git(self.a, "branch", "other")
        self.git(self.a, "config", "remote.origin.mirror", "true")
        self.assertIn("Uploaded", self.run_sync("end"))
        self.assertEqual(self.git(self.remote, "for-each-ref", "--format=%(refname)"), "refs/heads/trunk")

    def test_url_rewrite_applies_once_and_pruning_is_disabled(self):
        other = self.root / "wrong-remote.git"
        self.git(self.root, "clone", "--bare", "-q", str(self.remote), str(other))
        untouched = self.rev(other)
        alias = str(self.root / "remote-alias.git")
        self.git(self.a, "remote", "set-url", "origin", alias)
        self.git(self.a, "config", "url." + str(self.remote) + ".insteadOf", alias)
        self.git(self.a, "config", "url." + str(other) + ".insteadOf", str(self.remote))
        self.enable()
        self.git(self.a, "tag", "local-only")
        self.git(self.a, "config", "fetch.prune", "true")
        self.git(self.a, "config", "fetch.pruneTags", "true")
        self.commit(self.a, "local.txt", "new\n")
        self.assertIn("Uploaded", self.run_sync("end"))
        self.assertEqual(self.rev(self.remote), self.rev(self.a))
        self.assertEqual(self.rev(other), untouched)
        self.assertEqual(self.git(self.a, "tag"), "local-only")

    def test_lock_prevents_two_apps_syncing_or_changing_policy_at_once(self):
        self.enable()
        with local_state.lock(project.lock_key(str(self.a)), wait=0):
            with patch.object(project, "synchronize", side_effect=AssertionError("overlap")):
                self.assertIn("Another playbook operation", self.run_sync())
            with self.assertRaises(RuntimeError):
                self.enable(mode="local")

    def test_concurrent_status_records_preserve_both_apps_and_parts(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda item: playbook.record(*item, str(self.a), 10),
                          [(app, part) for app in ("codex", "claude") for part in ("rules", "context")]))
        data = local_state.read("status.json")
        self.assertEqual(set(data), {"codex", "claude"})
        for app in data:
            self.assertEqual(set(data[app]), {"rules", "context"})
            self.assertEqual(data[app]["context"]["version"], "1.2.0")

    def test_corrupt_state_blocks_without_replacing_it(self):
        self.enable()
        (self.state / project.REGISTRY).write_text("invalid")
        self.assertIn("Tell the user", self.run_sync())
        self.assertEqual((self.state / project.REGISTRY).read_text(), "invalid")
        with self.assertRaises(ValueError):
            self.enable(mode="ask")


if __name__ == "__main__":
    unittest.main()
