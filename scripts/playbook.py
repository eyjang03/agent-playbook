#!/usr/bin/env python3
"""Agent Playbook session-start context for Claude Code and Codex.

  playbook.py start --app claude|codex --part rules     core rules + the user's personal rules
  playbook.py start --app claude|codex --part context   memory bridge + project handoff
  playbook.py status                                     when the hooks last ran, and what they found
  playbook.py test                                       self-check in a throwaway home folder

Prints the SessionStart JSON both apps accept. Always exits 0 so a problem here
never breaks a session. Needs only Python 3.9+ (the macOS system Python works).
"""
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PART_LIMIT = 9000  # characters per hook output; each part stays well under the apps' limits
HANDOFF_LINES = 60


def home(*parts):
    return os.path.join(os.path.expanduser("~"), *parts)


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeDecodeError):
        return ""


def git(repo, *args):
    try:
        r = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def project_root(cwd):
    return git(cwd, "rev-parse", "--show-toplevel") or cwd


def clip(text, source):
    if len(text) <= PART_LIMIT:
        return text
    return text[:PART_LIMIT].rsplit("\n", 1)[0] + "\n... (truncated; open %s for the rest)" % source


# --- rules -------------------------------------------------------------------

def rules_part():
    core = read(os.path.join(ROOT, "rules", "core-rules.md")).strip()
    personal = read(home(".agent-playbook", "personal.md")).strip()
    text = core + ("\n\n# Personal rules\n\n" + personal if personal else "")
    return clip(text, "the agent-playbook rules files")


# --- memory bridge -------------------------------------------------------------

def topic_matches(heading, project):
    name = os.path.basename(project).lower()
    heading = heading.lower()
    if name and name in heading:
        return True
    home_path = os.path.expanduser("~").lower()
    words = [w for w in re.findall(r"[a-z0-9]{4,}", name) if w not in home_path]
    return any(w in heading for w in words)


def codex_memory_for(project):
    """Codex's summary: general sections plus only the topics about this project."""
    text = read(home(".codex", "memories", "memory_summary.md"))
    if not text:
        return ""
    keep, h2, include_topic = [], "", False
    for line in text.splitlines():
        if line.startswith("## "):
            h2, include_topic = line[3:].strip().lower(), False
        elif line.startswith("### ") and h2 == "what's in memory":
            include_topic = topic_matches(line, project)
        if h2 != "what's in memory" or line.startswith("## ") or include_topic:
            keep.append(line)
    body = "\n".join(keep).strip()
    return "Codex's memory summary (read-only background; may be out of date; topics about other projects left out):\n\n" + body


def claude_memory_for(project):
    slug = re.sub(r"[^A-Za-z0-9-]", "-", project)
    path = home(".claude", "projects", slug, "memory", "MEMORY.md")
    text = read(path).strip()
    if not text:
        return ""
    return ("Claude's saved notes for this folder (read-only background; may be out of date). "
            "The linked files are in %s; open them only when relevant:\n\n%s" % (os.path.dirname(path), text))


# --- handoff -----------------------------------------------------------------

def handoff_for(project):
    path = os.path.join(project, "HANDOFF.md")
    lines = read(path).splitlines()
    if not lines:
        return ""
    out = ["HANDOFF.md (where the last session left off):", ""] + lines[:HANDOFF_LINES]
    if len(lines) > HANDOFF_LINES:
        out.append("... (open HANDOFF.md for the rest; it should be under %d lines)" % HANDOFF_LINES)
    last = git(project, "log", "-1", "--format=%H", "--", "HANDOFF.md")
    if last:
        changed = {f for f in git(project, "log", "--format=", "--name-only", last + "..HEAD").splitlines()
                   if f and f != "HANDOFF.md" and f != "LOG.md" and not f.startswith("log/")}
        if changed:
            count = git(project, "rev-list", "--count", last + "..HEAD")
            out += ["", "Note: %s commit(s) since HANDOFF.md was last updated changed other files "
                        "(%s). Recent work may be missing from the handoff; update it when you finish."
                    % (count, ", ".join(sorted(changed)[:4]) + (", ..." if len(changed) > 4 else ""))]
    return "\n".join(out)


def context_part(app, cwd):
    project = project_root(cwd)
    pieces = [handoff_for(project)]
    pieces.append(codex_memory_for(project) if app == "claude" else claude_memory_for(project))
    return clip("\n\n".join(p for p in pieces if p), "HANDOFF.md or the memory files")


# --- status ------------------------------------------------------------------

def record(app, part, cwd, chars):
    path = home(".agent-playbook", "status.json")
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        status = json.loads(read(path) or "{}")
        status.setdefault(app, {})[part] = {
            "last_run": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
            "folder": cwd, "characters": chars}
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(status, f, indent=2)
        os.replace(tmp, path)
    except (OSError, ValueError):
        pass


def status():
    data = json.loads(read(home(".agent-playbook", "status.json")) or "{}")
    for app in ("claude", "codex"):
        runs = data.get(app, {})
        if not runs:
            print("%s: never ran on this computer (plugin not installed, or Codex hooks not approved yet)" % app)
        for part, info in sorted(runs.items()):
            print("%s %s: last ran %s in %s (%s characters)" % (app, part, info["last_run"], info["folder"], info["characters"]))
    for mode, info in sorted(data.get("project-sync", {}).items()):  # written by eugene-setup's sync hooks
        print("project-sync %s: last ran %s in %s" % (mode, info["last_run"], info["folder"]))
    print("personal rules file: %s" % ("present" if read(home(".agent-playbook", "personal.md")) else "none (~/.agent-playbook/personal.md)"))
    print("Codex memory summary: %s" % ("present" if read(home(".codex", "memories", "memory_summary.md")) else "none"))
    return 0


# --- entry points --------------------------------------------------------------

def start(app, part, cwd):
    text = rules_part() if part == "rules" else context_part(app, cwd)
    record(app, part, cwd, len(text))
    if not text:
        return {}
    return {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}}


def main(argv):
    if len(argv) > 1 and argv[1] == "status":
        return status()
    if len(argv) > 1 and argv[1] == "test":
        return selftest()
    args = dict(zip(argv[2::2], argv[3::2]))
    out = {}
    try:
        payload = {} if sys.stdin.isatty() else json.loads(sys.stdin.read() or "{}")
        cwd = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
        if argv[1:2] == ["start"] and args.get("--app") in ("claude", "codex") and args.get("--part") in ("rules", "context"):
            out = start(args["--app"], args["--part"], cwd)
    except Exception:  # never break a session
        out = {}
    print(json.dumps(out))
    return 0


def selftest():
    tmp = tempfile.mkdtemp(prefix="playbook-test-")
    old_home = os.environ.get("HOME")
    os.environ["HOME"] = tmp
    os.environ.update(GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    try:
        project = os.path.join(tmp, "Documents", "My Project")
        os.makedirs(project)

        def write(path, text):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(text)

        def ctx(out):
            return out.get("hookSpecificOutput", {}).get("additionalContext", "")

        # Rules: core always, personal only when present.
        rules = ctx(start("claude", "rules", project))
        assert "Agent Playbook core rules" in rules and "Personal rules" not in rules
        write(os.path.join(tmp, ".agent-playbook", "personal.md"), "Prefer metric units.")
        assert "Prefer metric units." in ctx(start("codex", "rules", project))

        # Nothing to add in an empty folder.
        assert start("claude", "context", project) == {}

        # Memory bridge, Claude side: general sections plus only this project's topics.
        write(os.path.join(tmp, ".codex", "memories", "memory_summary.md"),
              "## User preferences\n- keep it short\n## What's in Memory\n"
              "### My Project work\n- note about this project\n### Other thing\n- unrelated note\n")
        text = ctx(start("claude", "context", project))
        assert "keep it short" in text and "note about this project" in text and "unrelated note" not in text

        # Memory bridge, Codex side: Claude's notes for this exact folder.
        slug = re.sub(r"[^A-Za-z0-9-]", "-", project)
        write(os.path.join(tmp, ".claude", "projects", slug, "memory", "MEMORY.md"), "- [Fact](fact.md) - a saved fact")
        assert "a saved fact" in ctx(start("codex", "context", project))

        # Handoff: shown, and flagged when later commits changed other files.
        subprocess.run(["git", "init", "-q", project], check=True)
        write(os.path.join(project, "HANDOFF.md"), "Next: write the intro.\n")
        subprocess.run(["git", "-C", project, "add", "HANDOFF.md"], check=True)
        subprocess.run(["git", "-C", project, "commit", "-qm", "handoff"], check=True)
        text = ctx(start("codex", "context", project))
        assert "write the intro" in text and "missing from the handoff" not in text
        write(os.path.join(project, "draft.md"), "work\n")
        subprocess.run(["git", "-C", project, "add", "draft.md"], check=True)
        subprocess.run(["git", "-C", project, "commit", "-qm", "draft"], check=True)
        assert "missing from the handoff" in ctx(start("codex", "context", project))

        # Status is recorded for each app and part, and output stays within the limit.
        data = json.loads(read(os.path.join(tmp, ".agent-playbook", "status.json")))
        assert set(data) == {"claude", "codex"} and "rules" in data["codex"] and "context" in data["codex"]
        assert len(clip("x\n" * PART_LIMIT, "f")) <= PART_LIMIT + 80
        assert len(rules_part()) <= PART_LIMIT + 80
    finally:
        if old_home is not None:
            os.environ["HOME"] = old_home
        subprocess.run(["rm", "-rf", tmp])
    print("playbook self-test: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
