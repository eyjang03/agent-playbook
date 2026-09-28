"""Run saved, real shell hook commands after deleting their whole plugin cache."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import build_hooks


class HookUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="playbook-hook-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.cache = self.root / "old cache ' with spaces"
        shutil.copytree(ROOT, self.cache, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        self.work = self.root / "project with spaces"
        self.work.mkdir()
        self.home = self.root / "home"
        self.home.mkdir()
        self.tmp = self.root / "tmp"
        self.tmp.mkdir()
        self.state = self.home / ".agent-playbook"
        self.env = dict(os.environ, HOME=str(self.home), AGENT_PLAYBOOK_HOME=str(self.state),
                        TMPDIR=str(self.tmp), PLUGIN_ROOT=str(self.cache), CLAUDE_PLUGIN_ROOT=str(self.cache),
                        GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.invalid",
                        GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.invalid")
        self.commands = {}
        for app, name in (("codex", "codex-hooks.json"), ("claude", "hooks.json")):
            doc = json.loads((self.cache / "hooks" / name).read_text())["hooks"]
            self.commands[app] = {"rules": doc["SessionStart"][0]["hooks"][0]["command"],
                                  "context": doc["SessionStart"][0]["hooks"][1]["command"]}

    def run_hook(self, app, action, command=None, payload=None):
        result = subprocess.run(["/bin/sh", "-c", command or self.commands[app][action]],
                                input=json.dumps(payload if payload is not None else {"cwd": str(self.work)}),
                                env=self.env, cwd=self.work, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        return json.loads(result.stdout)

    def git(self, cwd, *args):
        return subprocess.run(["git", "-C", str(cwd), *args], env=self.env,
                              check=True, capture_output=True, text=True).stdout.strip()

    def commit(self, filename, contents):
        (self.work / filename).write_text(contents)
        self.git(self.work, "add", filename)
        self.git(self.work, "commit", "-qm", "fixture")

    def test_generated_hooks_match_sources(self):
        for path, text in build_hooks.documents().items():
            self.assertEqual(path.read_text(), text, "Run scripts/build_hooks.py")

    def test_build_is_reproducible(self):
        self.assertEqual(build_hooks.bootstrap(ROOT), build_hooks.bootstrap(self.cache))

    def test_first_invocation_after_cache_deletion_loads_rules_and_records_version(self):
        shutil.rmtree(self.cache)
        self.state.mkdir()
        (self.state / "personal.md").write_text("Personal fixture preference")
        for app in self.commands:
            out = self.run_hook(app, "rules")
            context = out["hookSpecificOutput"]["additionalContext"]
            self.assertIn("Agent Playbook core rules", context)
            self.assertIn("Personal fixture preference", context)
            status = json.loads((self.state / "status.json").read_text())
            self.assertEqual(status[app]["rules"]["version"], json.loads((ROOT / ".codex-plugin/plugin.json").read_text())["version"])
        self.assertFalse(list(self.tmp.glob("agent-playbook-hook-*")))

    def test_cache_deletion_does_not_skip_handoff_or_memory_bridge(self):
        (self.work / "HANDOFF.md").write_text("# Handoff\nFixture handoff\n")
        codex = self.home / ".codex/memories"
        codex.mkdir(parents=True)
        (codex / "memory_summary.md").write_text("## General\nCodex memory fixture")
        import re
        slug = re.sub(r"[^A-Za-z0-9-]", "-", str(self.work))
        claude = self.home / ".claude/projects" / slug / "memory"
        claude.mkdir(parents=True)
        (claude / "MEMORY.md").write_text("Claude memory fixture")
        shutil.rmtree(self.cache)
        for app, memory in (("codex", "Claude memory fixture"), ("claude", "Codex memory fixture")):
            out = self.run_hook(app, "context")["hookSpecificOutput"]["additionalContext"]
            self.assertIn("Fixture handoff", out)
            self.assertIn(memory, out)

    def test_old_hook_never_switches_to_replacement_code(self):
        self.run_hook("codex", "rules")
        shutil.rmtree(self.cache)
        self.cache.mkdir()
        (self.cache / "scripts").mkdir()
        (self.cache / "scripts/playbook.py").write_text("raise RuntimeError('replacement must not execute')")
        for app in self.commands:
            self.assertIn("Agent Playbook core rules", self.run_hook(app, "rules")["hookSpecificOutput"]["additionalContext"])

    def test_no_stop_hook(self):
        # A failing Stop hook is retried by the host every turn; see build_hooks.py.
        for name in ("codex-hooks.json", "hooks.json"):
            self.assertEqual(set(json.loads((ROOT / "hooks" / name).read_text())["hooks"]), {"SessionStart"})

    def test_enrolled_hooks_upload_and_download_after_cache_deletion(self):
        remote = self.root / "remote.git"
        self.git(self.root, "init", "-q", "--bare", "-b", "main", str(remote))
        self.git(self.work, "init", "-q", "-b", "main")
        self.git(self.work, "remote", "add", "origin", str(remote))
        self.commit("README.md", "base\n")
        self.git(self.work, "push", "-q", "-u", "origin", "main")
        subprocess.run([sys.executable, str(self.cache / "scripts/project.py"), "configure",
                        "--project", str(self.work), "--mode", "auto", "--remote", "origin", "--branch", "main", "--download"],
                       env=self.env, check=True, capture_output=True, text=True)
        shutil.rmtree(self.cache)
        for app in self.commands:
            self.commit(app + ".txt", app)
            self.run_hook(app, "context")
            self.assertEqual(self.git(remote, "rev-parse", "main"), self.git(self.work, "rev-parse", "HEAD"))
            peer = self.root / (app + "-peer")
            self.git(self.root, "clone", "-q", str(remote), str(peer))
            (peer / "HANDOFF.md").write_text("Fresh handoff from " + app)
            self.git(peer, "add", "HANDOFF.md")
            self.git(peer, "commit", "-qm", "new handoff")
            self.git(peer, "push", "-q")
            context = self.run_hook(app, "context")["hookSpecificOutput"]["additionalContext"]
            self.assertIn("Fresh handoff from " + app, context)
            self.assertEqual(self.git(self.work, "rev-parse", "HEAD"), self.git(peer, "rev-parse", "HEAD"))

    def test_concurrent_hooks_use_separate_runtime_directories(self):
        shutil.rmtree(self.cache)
        actions = [(app, action) for app in self.commands for action in ("rules", "context")]
        with ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(lambda pair: self.run_hook(*pair), actions))
        status = json.loads((self.state / "status.json").read_text())
        for app in self.commands:
            self.assertEqual(set(status[app]), {"rules", "context"})
        self.assertFalse(list(self.tmp.glob("agent-playbook-hook-*")))

    def test_project_cannot_shadow_runtime_imports(self):
        for name in ("local_state.py", "project.py", "sitecustomize.py", "json.py"):
            (self.work / name).write_text("raise RuntimeError('project code must not execute')")
        self.env["PYTHONPATH"] = str(self.work)
        shutil.rmtree(self.cache)
        self.assertIn("hookSpecificOutput", self.run_hook("codex", "rules"))

    def test_corrupt_runtime_warns_without_retry_exit_code(self):
        for app in self.commands:
            for action in ("rules", "context"):
                args = shlex.split(self.commands[app][action])
                args[3] = args[3].replace('ARCHIVE_SHA256 = "', 'ARCHIVE_SHA256 = "invalid')
                out = self.run_hook(app, action, command=shlex.join(args))
                self.assertIn("did not complete", out["systemMessage"])
                self.assertIn("hookSpecificOutput", out)
        self.assertFalse((self.state / "status.json").exists())

    def test_zsh_can_run_the_saved_command_after_cache_deletion(self):
        zsh = shutil.which("zsh")
        if not zsh:
            self.skipTest("zsh is not installed")
        shutil.rmtree(self.cache)
        result = subprocess.run([zsh, "-c", self.commands["codex"]["rules"]],
                                input=json.dumps({"cwd": str(self.work)}), env=self.env,
                                cwd=self.work, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Agent Playbook core rules", json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"])


if __name__ == "__main__":
    unittest.main()
