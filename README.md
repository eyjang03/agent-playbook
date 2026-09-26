# Agent Playbook

A shared way of working for **Claude Code** and **Codex**: the same core rules in every session, tidy project notes that any app can pick up, a memory bridge for people who use both apps, and a one-step installer for a set of recommended tools.

## What it does

**At the start of every session** (both apps, also after a conversation is compacted):
- Loads the **core rules**: protecting your work, Git habits, how to keep project notes, checking work honestly, and plain communication. See `rules/core-rules.md`.
- Adds **your personal rules** from `~/.agent-playbook/personal.md`, if you have one.
- Shows the project's **`HANDOFF.md`** (where the last session left off) and warns when newer work isn't in it yet.
- **Memory bridge:** Claude sees Codex's memory summary (only the parts about the current project, plus general notes), and Codex sees Claude's saved notes for the current folder. Nothing is shared if you only use one app.

**Skills you can ask for**
- *"Set up my rules"*: writes your personal rules file after a few questions.
- *"Set up project notes"*: one `AGENTS.md` (merging any `CLAUDE.md` or `GEMINI.md`), a short `HANDOFF.md`, and a `LOG.md` only when the project needs one.
- *"Install the playbook tools"*: installs the recommended skills and plugins in both apps, asking first.
- *"Run the new model check"*: six everyday situations to see how a new AI model follows your rules.
- *"Storm research this"*: a multi-perspective, citation-verified HTML research briefing (five expert lenses, a contradiction map, and primary-source checks).

**It never** deletes, publishes, or changes account settings on its own; the rules tell the AI to ask first.

## Install

You need access to this private repository (ask Eugene for an invite) and to be signed in to GitHub (`gh auth login`).

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
Codex asks you to review and approve the plugin's hooks once; until then the rules don't load.

Then say *"Set up my rules"* and *"Install the playbook tools"*.

**Gemini users:** the Antigravity CLI reads `AGENTS.md` natively. The older Gemini CLI reads `GEMINI.md` by default and needs its context file setting changed to `AGENTS.md`.

## Check it's working

```
python3 scripts/playbook.py status     # when the hooks last ran, in each app
python3 scripts/playbook.py test       # self-test
```

Needs Python 3.9 or later (the macOS system Python works).

## License

MIT
