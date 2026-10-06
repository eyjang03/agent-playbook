# Agent Playbook

A shared way of working for **Claude Code** and **Codex**: core rules, project notes, a memory bridge, and guided setup for your preferences, projects, and optional tools.

## What it does

**At the start of every session** (both apps, also after a conversation is compacted):
- Loads the **core rules**: protecting your work, Git habits, how to keep project notes, checking work honestly, and plain communication. See `rules/core-rules.md`.
- Keeps unsolicited AI acknowledgments, tool credits, and AI-permission disclaimers out of deliverable files. Process notes stay in the conversation unless the user requests attribution.
- Adds **your personal rules** from `~/.agent-playbook/personal.md`, if you have one.
- Shows the project's **`HANDOFF.md`** (where the last session left off) and warns when newer work isn't in it yet.
- **Memory bridge:** Claude sees Codex's memory summary (only the parts about the current project, plus general notes), and Codex sees Claude's saved notes for the current folder. Nothing is shared if you only use one app.

**Skills you can ask for**
- *"Set up Agent Playbook on this computer"*: checks the apps you use, sets up your preferences once, and helps you choose projects and tools.
- *"Set up this project with Agent Playbook"*: sets up Git and, if you want it, a private repository in your own GitHub account. You choose whether uploads require approval or happen automatically.
- *"Set up my rules"*: writes your personal rules file after a few questions.
- *"Set up project notes"*: one `AGENTS.md` (merging any `CLAUDE.md` or `GEMINI.md`), a short `HANDOFF.md`, and a `LOG.md` only when the project needs one.
- *"Install the playbook tools"*: installs the recommended skills and plugins in both apps, asking first.
- *"Run the new model check"*: twelve everyday situations to see how a new AI model follows your rules.
- *"Storm research this"*: a multi-perspective, citation-verified HTML research briefing (five expert lenses, a contradiction map, and primary-source checks).
- *"Ask Gemini to do this"*: hands clear, simple tasks (and second-opinion reviews or video/audio) to Google Gemini through its official Antigravity CLI (`agy`), to save Claude and Codex usage. Uses the newest model, as few parallel calls as the work needs, and a resumable run folder if Gemini usage runs out. Needs `agy` installed and signed in.
- *"Have Codex audit this"* (or name a model and effort): runs an OpenAI model through the official Codex CLI as a read-only second-model reviewer, on an evidence pack the calling agent collects, with web search. Needs Codex installed and signed in.

The core rules guide the agent; they are not a technical gate on every tool call. The plugin does not intercept deployments or outgoing messages. Its Git helper enforces its own saved sync choices. Use the host app and service permissions when an action must be technically blocked.

Project uploads start only after you choose a destination and give permission. Automatic uploads are an optional standing permission for a specific checkout, branch, and remote. Installing the plugin does not enable them.

## Install

This repository is public, so you can install it without an invitation or GitHub sign-in. Your personal rules stay on your computer in `~/.agent-playbook/personal.md`; they are not part of this repository. No other personal plugin is required.

Needs Git and Python 3.9 or later. Project automation is tested on macOS. Check hook commands and local behavior before enabling automation on another operating system.

**Claude Code** (2.1.277 or later)
```
/plugin marketplace add eyjang03/agent-playbook
/plugin install agent-playbook@agent-playbook
```

**Codex**
```
codex plugin marketplace add eyjang03/agent-playbook
codex plugin add agent-playbook@agent-playbook
```
Codex requires you to review and approve the plugin's hooks before they run. Changed hook definitions can require renewed approval; until approved, those hooks do not load rules or context.

Then say *"Set up Agent Playbook on this computer"*.

Use both apps? Install in each, then set up personal rules once on that computer. Both read the same preferences file. Open the same project folder in either app. Repeat installation and project selection on another computer; a successful upload does not prove that computer has downloaded anything.

**Gemini users:** the Antigravity CLI reads `AGENTS.md` natively. The older Gemini CLI reads `GEMINI.md` by default and needs its context file setting changed to `AGENTS.md`.

## Choose projects and uploads

Ask *"Set up this project with Agent Playbook"* from a folder you want to use. The AI inspects the folder and existing Git history before proposing changes. New GitHub repositories default to private and belong to your account. Existing remotes and history are preserved.

| Your choice | What the hooks do |
|---|---|
| Local Git only | No network operations; commits stay on this computer. |
| Ask before uploading | No network operations; the AI requests any missing approval for a manual upload. |
| Automatic uploads | Check the selected remote and upload pending commits at session start. |
| Automatic uploads + downloads | Also download newer commits at session start when a fast-forward can preserve local work. |

Choices are saved locally in `~/.agent-playbook/projects.json`. They apply to both apps on this computer. A cloned repository, project instruction file, or another computer's setup cannot turn on uploads here. General rules and the memory bridge still load globally wherever the plugin is enabled.

Automatic sync handles committed work on the selected branch. It does not create commits, reconcile split histories, force-push, switch branches, or sync linked task worktrees. It pauses for a changed destination, incomplete Git operation, risky incoming path, or a failed credential scan. It requires an existing remote branch and complete history, and does not support submodules. Existing `.project-sync` setups need a migration decision before using this sync system.

Credential checks cover outgoing history, including content removed by later commits, but they cannot identify all secrets or private information. Review the files and history before the first upload. Large histories or files that exceed the scan limits require manual review.

Ask *"Keep this project's commits local"* to stop automatic network operations. Ask *"Change this project's upload settings"* to review its choices. Other plugins and tools keep their own behavior.

See [working tips](docs/working-tips.md) for optional habits drawn from using two AI apps across two computers. These include short handoffs, small commits, and checking work on the receiving computer. Use the parts that fit you.

## Check it's working

Run these from the installed plugin folder:

```
python3 scripts/playbook.py status     # when the hooks last ran, in each app
python3 scripts/playbook.py test       # self-test
python3 scripts/build_hooks.py --check # generated hooks match their runtime sources
python3 scripts/project.py status     # this computer's project choices and sync results
python3 -m unittest discover -s tests  # isolated Git tests, no GitHub account needed
```

After installation or an update, start a new session in each app. Check for fresh `rules` and `context` records with the expected version. Running a script by hand tests the code; it does not prove that an app has loaded its hooks. For automatic sync, also check that app's start and end records in the selected project.

The helpers normally use `~/.agent-playbook`. `AGENT_PLAYBOOK_HOME` can isolate project choices and status during development or testing; the personal rules file remains at its usual path.

## Update

Version 1.2.2 makes hooks independent of the installed plugin directory. An active
chat can keep running its original hook runtime after an update removes that
directory. When upgrading from 1.2.1 or earlier, reload existing sessions once;
their already-loaded commands cannot be replaced by a plugin update. See
[hook runtime and verification](docs/hook-runtime.md) for the design and limits.

Update each app separately. Refreshing the marketplace alone is not the same as updating the installed plugin.

Codex:

```sh
codex plugin marketplace upgrade agent-playbook
codex plugin add agent-playbook@agent-playbook
```

Claude Code, from a terminal:

```sh
claude plugin marketplace update agent-playbook
claude plugin update agent-playbook@agent-playbook
```

Review any renewed hook approval, start new sessions, and check the version records again. Your personal rules and project choices are outside the plugin cache, so updating the plugin preserves them.

## Prompt to give your AI

```text
Help me install and set up Agent Playbook from https://github.com/eyjang03/agent-playbook.

Read its README and check the prerequisites. Ask whether I use Codex, Claude Code,
or both, and install it in the apps I choose. Let me review hook permissions.
Use its setup-playbook skill, ask about my preferences, and show me the draft
before saving my shared personal rules once on this computer.

Offer the working tips as options. Ask which project folders I want to set up.
For each, preserve existing files, history, and remotes. Help me choose local Git,
approval before uploading, or automatic uploads. If I want GitHub, use my account
and propose a private repository. Show me the files, history, and destination
before the first upload. Offer multi-computer downloads separately.

Offer optional tools after the essentials. Verify fresh hook records in each app
I use, run the checks, explain how to update, and report anything still pending.
```

## License

MIT
