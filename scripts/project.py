#!/usr/bin/env python3
"""Local project choices and opt-in Git sync. Run with --help for commands.

No enrollment is inferred from repository files. Network operations require a
choice saved on this computer for this exact checkout and remote. Hooks never
initialize, stage, commit, switch branches, reconcile splits, or force-push.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.parse import urlsplit

import local_state

REGISTRY = "projects.json"
SECRETS = re.compile(rb"|".join([
    rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----",
    rb"\bAKIA[0-9A-Z]{16}\b", rb"\bxox[abprs]-[0-9A-Za-z-]{10,}",
    rb"\bsk-[A-Za-z0-9_-]{20,}\b", rb"\bgh[pousr]_[0-9A-Za-z]{30,}\b",
    rb"\bgithub_pat_[0-9A-Za-z_]{40,}\b", rb"\bAIza[0-9A-Za-z_-]{35}\b",
]))


class Blocked(RuntimeError):
    pass


def git(repo, *args, timeout=15, binary=False):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="never",
               GIT_SSH_COMMAND="ssh -oBatchMode=yes -oConnectTimeout=10")
    try:
        result = subprocess.run(["git", "--no-replace-objects", "-C", str(repo), *args],
                                capture_output=True, timeout=timeout, env=env)
    except (OSError, subprocess.TimeoutExpired):
        raise Blocked("Git was unavailable or timed out. Check the connection and local Git setup.")
    if result.returncode:
        # Remote errors can contain credential-bearing URLs. Never echo them.
        operation = next((a for a in args if a in ("fetch", "push", "merge")), args[0])
        raise Blocked("Git could not complete '%s'. Check authentication, connectivity, and repository state." % operation)
    if binary:
        return result.stdout
    text = result.stdout.decode("utf-8", "surrogateescape")
    return text if "-z" in args else text.strip()


def optional_git(repo, *args):
    try:
        return git(repo, *args)
    except Blocked:
        return ""


def locate(folder):
    root = optional_git(folder, "rev-parse", "--show-toplevel")
    return str(Path(root).resolve()) if root else None


def identity(repo):
    common = Path(repo, git(repo, "rev-parse", "--git-common-dir")).resolve()
    own = Path(repo, git(repo, "rev-parse", "--git-dir")).resolve()
    stat = common.stat()
    return {"git_dir": str(common), "device": stat.st_dev, "inode": stat.st_ino}, own != common


def endpoint(value):
    if not value or value.startswith("-") or any(c in value for c in "\n\r\0") or "::" in value:
        raise Blocked("Use a standard HTTPS, SSH, or local Git remote.")
    if "://" in value:
        url = urlsplit(value)
        if url.scheme not in ("https", "ssh", "file") or url.password or url.query or url.fragment:
            raise Blocked("Use a remote without embedded credentials, query parameters, or remote helpers.")
        if url.scheme == "https" and url.username:
            raise Blocked("Use HTTPS without a username or token in the URL; authenticate with Git's credential helper.")
    return value


def binding(repo, remote):
    if remote not in git(repo, "remote").splitlines():
        raise Blocked("The selected remote does not exist.")
    fetch = git(repo, "remote", "get-url", "--all", remote).splitlines()
    push = git(repo, "remote", "get-url", "--push", "--all", remote).splitlines()
    if len(fetch) != 1 or len(push) != 1 or fetch != push:
        raise Blocked("Automatic sync needs one matching fetch and push destination. Review this remote manually.")
    return {"remote": remote, "url": endpoint(fetch[0])}


def validate_policy(policy):
    if not isinstance(policy, dict) or policy.get("version") != 1 or policy.get("mode") not in ("local", "ask", "auto"):
        raise Blocked("Project settings are invalid; review them with the project-setup skill.")
    if type(policy.get("download")) is not bool or not isinstance(policy.get("identity"), dict):
        raise Blocked("Project settings are incomplete; review them before syncing.")
    if policy["mode"] != "auto" and policy["download"]:
        raise Blocked("Downloads require an explicit automatic-sync choice.")


def load_policy(repo):
    policy = local_state.read(REGISTRY).get(repo)
    if policy is not None:
        validate_policy(policy)
    return policy


def lock_key(repo):
    return "project-" + hashlib.sha256(repo.encode()).hexdigest()[:24]


def automatic_ready(repo):
    if Path(repo, ".project-sync").exists():
        raise Blocked("This project has an existing .project-sync setup. Keep one sync system; review migration first.")
    if git(repo, "rev-parse", "--is-shallow-repository") == "true":
        raise Blocked("Automatic sync requires complete history. Review this shallow clone manually.")
    if any(line.startswith(b"160000 ") for line in git(repo, "ls-files", "--stage", "-z", binary=True).split(b"\0")):
        raise Blocked("This project has submodules. Use manual uploads for this project.")
    for marker in ("MERGE_HEAD", "REBASE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "sequencer", "index.lock"):
        if Path(repo, git(repo, "rev-parse", "--git-path", marker)).exists():
            raise Blocked("A Git operation is in progress. Finish it before syncing.")


def configure(folder, mode, remote=None, branch=None, download=False):
    repo = locate(folder)
    if repo != str(Path(folder).resolve()):
        raise Blocked("Select the exact Git root before saving choices; do not enroll a parent repository by accident.")
    ident, linked = identity(repo)
    if linked:
        raise Blocked("Save choices from the main checkout, not a linked worktree.")
    policy = {"version": 1, "mode": mode, "download": download, "identity": ident}
    validate_policy(policy)
    if mode != "local":
        if not remote or not branch:
            raise Blocked("Choose the remote and branch explicitly.")
        git(repo, "check-ref-format", "refs/heads/" + branch)
        policy.update(binding(repo, remote), branch=branch)
        if mode == "auto":
            automatic_ready(repo)
            if git(repo, "symbolic-ref", "--short", "HEAD") != branch:
                raise Blocked("Select the branch currently checked out before enabling automatic uploads.")
            git(repo, "rev-parse", "--verify", "HEAD")
    with local_state.lock(lock_key(repo), wait=0):
        local_state.update(REGISTRY, lambda data: data.update({repo: policy}))
    return {"project": repo, "policy": policy, "network_used": False}


def inspect(folder):
    repo = locate(folder)
    if not repo:
        return {"selected_folder": str(Path(folder).resolve()), "git_root": None, "policy": None}
    ident, linked = identity(repo)
    remotes = {}
    for name in git(repo, "remote").splitlines():
        try:
            remotes[name] = binding(repo, name)["url"]
        except Blocked:
            remotes[name] = "Needs manual review (multiple destinations or a credential-bearing URL)."
    return {"selected_folder": str(Path(folder).resolve()), "git_root": repo,
            "linked_worktree": linked, "branch": optional_git(repo, "symbolic-ref", "--short", "HEAD"),
            "remotes": remotes, "policy": load_policy(repo),
            "tracked_files": len(git(repo, "ls-files", "-z", binary=True).split(b"\0")) - 1,
            "has_local_changes": bool(git(repo, "status", "--porcelain", "-z")),
            "legacy_sync": Path(repo, ".project-sync").exists()}


def secret_scan(repo, base, head):
    """Scan all outgoing objects, including secrets removed by a later commit."""
    span = base + ".." + head if base else head
    lines = git(repo, "rev-list", "--objects", span).splitlines()
    total = 0
    deadline = time.monotonic() + 30
    for line in lines:
        if time.monotonic() >= deadline:
            raise Blocked("Upload needs manual review: the history scan exceeded its time limit.")
        oid, _, name = line.partition(" ")
        leaf = name.rsplit("/", 1)[-1].lower()
        if (leaf == ".env" or (leaf.startswith(".env.") and leaf not in (".env.example", ".env.sample", ".env.template"))
                or leaf in ("id_rsa", "id_ed25519", "credentials.json") or leaf.endswith((".p12", ".pfx", ".pem"))):
            raise Blocked("Upload blocked: outgoing history includes a likely credential file. Review the commits locally.")
        kind = git(repo, "cat-file", "-t", oid)
        if kind not in ("blob", "commit", "tag"):
            continue
        size = int(git(repo, "cat-file", "-s", oid))
        total += size
        if size > 16 * 1024 * 1024 or total > 64 * 1024 * 1024:
            raise Blocked("Upload needs manual review: outgoing objects exceed the automatic scan limit.")
        if SECRETS.search(git(repo, "cat-file", kind, oid, binary=True)):
            raise Blocked("Upload blocked: outgoing history looks like it contains a credential, possibly in an earlier commit.")


def download_safe(repo, head, target):
    if git(repo, "status", "--porcelain", "-z"):
        raise Blocked("Download paused: this folder has uncommitted or untracked work. Save it before syncing.")
    tracked = set(git(repo, "ls-files", "-z").split("\0"))
    changed = git(repo, "diff", "--name-only", "-z", "--no-renames", head, target).split("\0")
    for name in filter(None, changed):
        path = Path(repo, name)
        if os.path.lexists(path) and (name not in tracked or path.is_dir() or path.is_symlink()):
            raise Blocked("Download paused: incoming paths overlap ignored files, directories, or symlinks. Review locally.")
        for parent in path.parents:
            if parent == Path(repo):
                break
            if os.path.lexists(parent) and (parent.is_symlink() or not parent.is_dir()):
                raise Blocked("Download paused: an incoming path crosses a local file or symlink.")
    if any(line.startswith("160000 ") for line in git(repo, "ls-tree", "-r", target).splitlines()):
        raise Blocked("Download paused: incoming history introduces a submodule. Review manually.")


def verify_binding(repo, policy):
    ident, linked = identity(repo)
    if linked or ident != policy["identity"]:
        raise Blocked("This checkout changed since setup. Review and save its project choices again.")
    if binding(repo, policy["remote"]) != {"remote": policy["remote"], "url": policy["url"]}:
        raise Blocked("The remote changed since setup. Review the destination before syncing.")
    if optional_git(repo, "symbolic-ref", "--short", "HEAD") != policy["branch"]:
        raise Blocked("This checkout is on another branch or detached HEAD. Automatic sync is paused; do not switch it without the user's agreement.")
    automatic_ready(repo)


def synchronize(repo, policy, phase):
    verify_binding(repo, policy)
    head = git(repo, "rev-parse", "HEAD")
    # Use the verified remote name so Git applies URL rewriting exactly once.
    # Explicit refspecs and flags prevent mirror, tag, or pruning configuration
    # from widening the operation.
    # Fetch into a private ref so a missing branch or failed fetch cannot use stale data.
    ref = "refs/agent-playbook/sync"
    git(repo, "fetch", "--quiet", "--no-tags", "--no-prune", "--no-prune-tags",
        "--no-recurse-submodules", "--no-write-fetch-head", "--refmap=",
        policy["remote"], "+refs/heads/" + policy["branch"] + ":" + ref, timeout=25)
    target = git(repo, "rev-parse", ref)
    behind, ahead = map(int, git(repo, "rev-list", "--left-right", "--count", target + "..." + head).split())
    if ahead and behind:
        raise Blocked("Local and remote history have split (%d local, %d remote commits). Nothing was reconciled; ask before merging or rebasing." % (ahead, behind))
    if behind:
        if phase != "start" or not policy["download"]:
            raise Blocked("The remote has %d newer commit(s). Download is pending; no upload was attempted." % behind)
        download_safe(repo, head, target)
        verify_binding(repo, policy)
        if git(repo, "rev-parse", "HEAD") != head:
            raise Blocked("Another task changed this checkout. Try again after it finishes.")
        git(repo, "-c", "merge.autoStash=false", "merge", "--ff-only", "--no-edit", "--no-autostash", target)
        return "Downloaded %d commit(s) into this computer's checkout." % behind
    if ahead:
        secret_scan(repo, target, head)
        verify_binding(repo, policy)
        if git(repo, "rev-parse", "HEAD") != head:
            raise Blocked("Another task changed this checkout during review. Upload is deferred.")
        git(repo, "-c", "push.followTags=false", "-c", "push.recurseSubmodules=no",
            "-c", "remote." + policy["remote"] + ".mirror=false",
            "push", "--porcelain", "--no-mirror", "--no-follow-tags", policy["remote"],
            head + ":refs/heads/" + policy["branch"], timeout=25)
        return "Uploaded %d commit(s). Receipt on another computer has not been checked." % ahead
    return "In sync with the selected remote branch on this computer."


def run(phase, cwd, app):
    repo = locate(cwd)
    if not repo:
        return ""
    try:
        policy = load_policy(repo)
        if not policy or identity(repo)[1]:
            return ""
        if policy["mode"] != "auto":
            return ("Project upload choice: %s. Hooks perform no network operations; ask before any upload."
                    % ("local Git only" if policy["mode"] == "local" else "ask before uploading")) if phase == "start" else ""
        with local_state.lock(lock_key(repo), wait=0):
            # A disable/change while another app is waiting must take effect immediately.
            if load_policy(repo) != policy:
                raise Blocked("Project choices changed. Recheck setup before syncing.")
            message = synchronize(repo, policy, phase)
        outcome = "ok"
    except Exception as exc:
        message = str(exc) if isinstance(exc, (Blocked, RuntimeError)) else "Project sync could not read its local settings. Review them before retrying."
        message = "Tell the user: " + message
        outcome = "blocked"
    try:
        def save(data):
            data.setdefault(repo, {}).setdefault(app, {})[phase] = {
                "last_run": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
                "outcome": outcome, "message": message}
        local_state.update("project-status.json", save)
    except Exception:
        pass
    return message


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("inspect", "configure", "disable", "check-upload"):
        cmd = sub.add_parser(name)
        cmd.add_argument("--project", required=True, help="Exact project folder")
        if name == "configure":
            cmd.add_argument("--mode", choices=("local", "ask", "auto"), required=True)
            cmd.add_argument("--remote")
            cmd.add_argument("--branch")
            cmd.add_argument("--download", action="store_true", help="Also permit fast-forward downloads at session start")
        if name == "check-upload":
            cmd.add_argument("--base", help="Verified remote commit; omit to scan all history before first upload")
    cmd = sub.add_parser("hook")
    cmd.add_argument("phase", choices=("start", "end"))
    cmd.add_argument("--app", choices=("codex", "claude"), required=True)
    sub.add_parser("status")
    args = parser.parse_args()
    try:
        if args.command == "inspect":
            result = inspect(args.project)
        elif args.command == "configure":
            result = configure(args.project, args.mode, args.remote, args.branch, args.download)
        elif args.command == "disable":
            repo = str(Path(args.project).resolve())
            with local_state.lock(lock_key(repo), wait=0):
                local_state.update(REGISTRY, lambda data: data.pop(repo, None))
            result = {"project": repo, "policy_removed": True}
        elif args.command == "check-upload":
            repo = locate(args.project)
            if not repo:
                raise Blocked("Select a Git repository.")
            base = git(repo, "rev-parse", "--verify", args.base + "^{commit}") if args.base else None
            secret_scan(repo, base, git(repo, "rev-parse", "HEAD"))
            result = {"scan": "passed", "note": "A pattern scan does not replace review of files and history."}
        elif args.command == "status":
            result = {"choices": local_state.read(REGISTRY), "runs": local_state.read("project-status.json")}
        else:
            payload = json.loads(sys.stdin.read() or "{}")
            message = run(args.phase, payload.get("cwd") or os.getcwd(), args.app)
            if args.phase == "start":
                result = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "[agent-playbook project] " + message}} if message else {}
            else:
                result = {"systemMessage": "agent-playbook project: " + message} if message else {}
        print(json.dumps(result, indent=2))
        return 0
    except Exception as exc:
        message = str(exc) if isinstance(exc, Blocked) else "Could not read or save local project settings. Inspect them before retrying."
        print(json.dumps({"systemMessage" if args.command == "hook" else "error": message}))
        return 0 if args.command == "hook" else 1


if __name__ == "__main__":
    sys.exit(main())
