# Multi-model audit: sandbox reference

How `scripts/` work, what a reviewer can and cannot do, how to qualify a Mac, and what remains open. The design was reviewed in eight audit rounds by GPT-6.2 Astra, GPT-6.2 Sol, Claude Fable 5.2 and Gemini 4 Neon (high effort) in November 2026; every finding was verified and fixed, and the loop stopped when the remaining findings were edge cases. Tested on macOS 27 (Apple Silicon) with Claude Code 2.1.3xx, Codex 0.169 and Antigravity 1.5.12.

## Scripts

| File | Role |
| --- | --- |
| `run-reviewer.sh` | Launcher: validates the folder layout, freezes the pack, builds the profile, fingerprints the inputs, starts the CLI under `sandbox-exec`, enforces the time limit, cleans up and collects the report. Read in full before it runs, so editing it cannot disturb a running reviewer. |
| `mkprofile.sh` | Writes the sandbox profile for one reviewer and checks the grants. |
| `inputs.py` | Hashes inputs as data (projects, files, packs, agy history) without following links, executing anything or blocking on special files; every mode has a deadline. |
| `boxcheck.c` | Compiled per run: finds this reviewer's processes anywhere on the Mac by their sandbox, so cleanup also catches a process that detached. |
| `capcheck.sh`, `capcheck-setup.sh`, `t.tex` | Capability check: a reviewer runs `capcheck.sh` inside; `capcheck-setup.sh` makes the fixtures and positive controls outside and confirms from outside at teardown. |

Settings (environment variables): `AUDIT_CODEX_HOME` (Codex home for Codex reviewers, for example a second account's; default `~/.codex`), `AUDIT_PROTECTED` (colon-separated folders no grant may open, such as a folder that holds many projects), `AUDIT_TIMEOUT_MIN` (default 240), `CLAUDE_BIN`, `CODEX_BIN`, `AGY_BIN` (CLI paths), `AUDIT_HIDE_FIXTURE=yes` (qualification only).

## What a reviewer gets

The launcher starts the CLI with a clean environment (`env -i`; temp, matplotlib, IPython and Jupyter folders in the reviewer's `tmp`; `GIT_CONFIG_GLOBAL=/dev/null`). The CLI's own sandbox is off, because macOS refuses nested sandboxes; the outer sandbox is the boundary. Claude cannot save a renewed sign-in from inside the sandbox, so before a Claude reviewer starts the launcher renews it with one tiny request outside (an empty folder, safe mode, no tools, two-minute limit), notes in the record if the sign-in will still expire within the time limit, and stops with a message if even that request fails.

- **Open:** commands of any kind; package installs into the reviewer's folder; the public web; the granted project and runtimes, read-only, with Git on them; the Tectonic LaTeX cache, read-only; the reviewer's own new terminals. Notebooks: kernels that talk over local sockets are unavailable, but an in-process kernel works (`ipykernel.inprocess.manager.InProcessKernelManager`), or convert with `jupyter nbconvert --to script`. Claude gets Agent, Bash, Read, Write, Edit, NotebookEdit, WebFetch, WebSearch, Monitor, TaskStop and ToolSearch without prompts; Codex runs with `danger-full-access`, web search and its sub-agents, connectors off; agy runs with its terminal sandbox off and allow rules for commands, file reads and writes, web pages and downloads.
- **Closed, files:** writes outside the reviewer's `pack` and `tmp` (and each CLI's own runtime files); reads under `/Users`, `/tmp`, the per-user temp and cache folders and `/Volumes` except what is granted; hard links and clones out of the reviewer's folder. Each CLI's settings, hooks, instructions, skills, plugins and memories are locked; Codex reads its login read-only; agy may change only the content of its two-line shell helper, which the launcher writes clean before and checks after every run.
- **Closed, other channels:** signals to processes outside the sandbox; launchd jobs (new ones, and `kill`, `kickstart` or `bootout` of existing ones); app launches; Apple Events; keyboards and input event taps; other sessions' terminals; Spotlight; Shortcuts (the services are denied and listing fails; whether a run request would be stopped is not verified); microphone and camera; preferences; the clipboard; mounts; connections to services on this Mac on any of its own addresses, in IPv4 and IPv6 form (including `::ffff:` mapped addresses), and over Unix sockets. IPv6 connections are closed altogether, so IPv6-only sites are unreachable; dual-stack sites, package indexes and the model APIs work over IPv4. On an IPv6-first network, a client that does not fall back to IPv4 fails: qualify each Mac on the network it uses.
- **Cleanup:** the launcher stops the CLI's process group, every descendant it recorded (only if still the same process) and every process `boxcheck` finds in this reviewer's sandbox. Unsandboxed processes are never signalled, only noted. A survivor, or a scan that fails or cannot classify a live process, rejects the run.
- **Binding:** every attempt starts from a frozen `pack-master` (regular files and folders only; type, executable bit and contents hashed). The launcher fingerprints each granted input as data before and after the run (Git only lists files, with fsmonitor and hooks off, so nothing configured in the repository runs). The round's first reviewer records the fingerprints, its canonical grants and its shared pack (everything except `PROMPT.md`, `context/previous-own-report.md` and `tools/capcheck.conf`); a change during a run, or a reviewer whose inputs, grants or shared pack differ, invalidates that result (before the CLI starts, when visible then). The attempt folder names the changed files.
- **Grants refused:** anything that would open the home folder or a loose file in it, `~/Documents`, `~/Desktop`, `~/Downloads`, a folder in `AUDIT_PROTECTED`, another project's files, a CLI's state or login, `~/Library`, `~/.ssh`, `~/.config`, the audit folder or another reviewer. A project grant must be a Git repository's top folder. Python environment bases are granted automatically only from known installers in home (uv, pyenv, asdf, mise, conda; a conda base keeps its other environments closed); anything else needs an explicit `runtime:` grant.

## Known gaps

macOS's sandbox cannot close the first three; running reviewers as a separate macOS user would close the first, the keychain gap and the shared CLI state (not yet tested: a background account's keychain stays locked, which affects CLIs that sign in through it).

- Any reviewer can read the arguments and environment variables of the user's other processes, which can hold session tokens of other CLI sessions.
- Other devices on the local network and VPN or tailnet are reachable; what a reviewer can do there depends on each service's own authentication.
- System services other than the closed ones stay reachable (the profile allows by default and denies named channels).
- Codex's commands can read its own login and share the runtime logs and databases of its Codex home.
- agy's commands can read and change its own conversation history and memory folders (changes to conversations idle for an hour at launch are detected by content hash and reject the run) and reach and listen on this Mac's own addresses (its helper server needs localhost); its tool list includes scheduling and messaging tools that cannot be switched off individually. An unsandboxed agy session running during an agy review could run a tampered helper before the launcher restores it.
- Claude's and agy's commands can read keychain items that trust `/usr/bin/security` (both sign in through it); the qualification lists which common items are reachable.

## Qualification

On each Mac, before the first audit and after any change to macOS, a CLI or these scripts. Run it from the agent app on that Mac (an SSH session cannot use the keychain, and a job started over SSH cannot read `~/Documents`).

1. Make an audit folder (`mktemp -d /tmp/audit-XXXXXX`, then `: > .audit-folder`) and, for each CLI, its own round folder with one reviewer folder: `$A/<cli>/<cli>/pack/PROMPT.md` asking it to run exactly `bash tools/capcheck.sh <cli>` and reply with `VERDICT: READY`, the output, `## Required changes` (None) and `## Checks performed`.
2. `AUDIT_HIDE_FIXTURE=yes scripts/capcheck-setup.sh setup <reviewer> <another reviewer> <launcher folder> <cli> [project python] [git project]` for each CLI. It makes unique fixtures, each with a positive control outside the sandbox, and writes two grants to `<reviewer>/capcheck-grants` for a disposable project whose record and `.git` must stay hidden. It never shows a permission prompt: keyboard checks run only where the starting app already has Input Monitoring.
3. Run each CLI with a cheap model through `run-reviewer.sh`, granting the git project and the two fixture grants.
4. Read the result from `<reviewer>/tmp/capcheck-result.txt` (a cheap model may copy only part of the output or answer READY regardless) and require `FAILED=0`; the expected number of checks depends on what works on that Mac.
5. `scripts/capcheck-setup.sh teardown <reviewer>` must exit 0: it confirms from outside that no background job, local-service connection or app-socket connection happened, and removes the fixtures.
