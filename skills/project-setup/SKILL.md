---
name: project-setup
description: Sets up Git and optional GitHub uploads or multi-computer sync for project folders the user selects. Use to choose or change a project's local-only, ask-before-upload, or automatic upload behavior, or troubleshoot Agent Playbook project sync.
---

# Set up a selected project

The helper is `scripts/project.py` in this plugin's folder. Read its `--help` before using unfamiliar commands. Quote paths. Saved choices live in `~/.agent-playbook/projects.json`, shared by both apps on this computer. Repository files cannot opt a person into uploads.

## Inspect and choose

Run `python3 scripts/project.py inspect --project "/chosen/folder"`. Also inspect existing instructions, Git status, history, ignored files, and remotes without printing credentials. If the Git root is a parent of the selected folder, show that boundary and ask which root is intended. Do not initialize a nested repository or enroll the parent automatically. Preserve nested repositories, symlinks, existing remotes, history, uncommitted changes, and ignored artifacts.

Ask for the choices that are still missing:

- **Local Git only:** commits stay on this computer; no automatic network operations.
- **Ask before uploading:** use a Git remote, but ask before each upload unless the user already authorized that specific upload in the current task. Hooks do no network operations.
- **Automatic uploads:** every commit on the selected branch may be uploaded at session start, including commits made by the other app or by the person. This is standing permission for that destination and branch, not permission to publish elsewhere or change visibility.
- For automatic uploads, separately offer **fast-forward downloads at session start** if they want work to travel between computers. Explain that split history needs a decision and that this is session-based sync, not a background file backup.

Recommend local Git or ask-before-upload until they are comfortable with the scope. Automatic uploads with downloads match the author's multi-computer workflow, but remain optional. Select the actual default branch from repository evidence; never assume it is `main`. Keep an existing team branching workflow.

## Git and GitHub

For a folder without Git, review its contents and ignore rules before `git init`. Use the person's Git identity, preferably configured locally for this repository. Do not reuse the plugin author's identity. Show the intended tracked scope, then stage explicit paths and review `git diff --cached`. Do not blanket-add home folders, project umbrellas, cloud-drive mounts, nested repositories, environment files, recordings, or datasets. Commit the agreed files only.

For GitHub, use their own account. Check `gh auth status` and `gh api user --jq .login`; let them complete sign-in locally if needed. Never request a token in chat. Preserve an existing origin. If it belongs to another person or organization, explain it and resolve the intended destination before making any change.

For a new repository, propose the exact owner/name, **private** visibility, selected folder, and files/history to upload. Reuse approval already given for that exact scope. Once approved, `gh repo create OWNER/NAME --private --source="/chosen/folder" --remote=origin` creates the destination without uploading. Do not pass `--push` here. Verify the new owner, URL, and visibility. Source: [GitHub CLI repository creation](https://cli.github.com/manual/gh_repo_create).

Before the first upload, inspect **all outgoing history**, not just the current tree, and run `python3 scripts/project.py check-upload --project "/chosen/folder"`. For subsequent manual uploads, use `--base VERIFIED_REMOTE_COMMIT` after fetching the approved destination. The pattern scan catches some credentials; it cannot determine whether personal or proprietary content belongs online. A failed or incomplete scan needs review, not a bypass or an automatic history rewrite. Show the reviewed scope and destination, obtain any still-missing upload approval, then push the selected branch explicitly. Verify it arrived. A private remote protects only tracked, uploaded history; ignored and uncommitted files are not backed up.

## Save the choices

Once the person's choice is clear, configure the **exact Git root**:

```sh
python3 scripts/project.py configure --project "/chosen/folder" --mode local
python3 scripts/project.py configure --project "/chosen/folder" --mode ask --remote origin --branch BRANCH
python3 scripts/project.py configure --project "/chosen/folder" --mode auto --remote origin --branch BRANCH
```

Use only the command matching their choice. Add `--download` to automatic mode only when downloads are also approved. Configuration saves local choices without contacting the remote. Complete and verify the first upload before enabling automatic mode; hooks require an existing remote branch.

Automatic mode binds this checkout, one matching fetch/push URL, and the selected branch. It pauses if they change, the checkout is replaced, history splits, a scan fails, or a Git operation is unfinished. It does not support shallow clones or submodules. Linked worktrees remain outside automatic sync. Existing `.project-sync` setups are left to their current plugin: do not enable this second sync system or remove the existing setup without a migration decision.

To stop automatic operations, set `--mode local`. `disable --project "/chosen/folder"` forgets this plugin's saved choice; it does not disable another plugin or remove the Git remote. Update any project note that still describes the old choice. Settings must be reviewed separately on every computer, even after cloning an enrolled project.

Use `project-notes` to agree on `AGENTS.md` and a short `HANDOFF.md`. Add only useful project-specific facts, including the intended repository and workflow. Do not put this computer's upload permission or local state files into a shared repository. Existing project rules still apply.

## Verify

Run `python3 scripts/project.py status`. For automatic mode, verify a fresh session-start run from each app they use in this project. A manual `hook` invocation can test sync after approval, but is not proof of app integration. Finish any authorized independent setup while app approval or another computer's check is pending. Never claim the second computer has downloaded work without checking it there.
