---
name: gemini
description: Delegate a task to Google Gemini through the official Antigravity CLI (`agy`). Main use is saving Claude and Codex usage by handing Gemini clear, simple, well-scoped work (specific coding changes, bulk edits, extraction, summaries, boilerplate). Also use, at lower priority, for an independent second opinion from a different model family (the "review by a different AI model" the core rules offer for risky work) and for video or audio understanding, and whenever the user says "ask Gemini", "Antigravity", or "agy". Not for work that needs the calling agent's own MCP connectors, skills, or browser, or that would send patient or client records, or other people's personal data, to Google.
---

# Gemini via Antigravity CLI

Always go through `agy`, Google's own client. Never route Antigravity's login through a third-party tool or proxy (such as OpenCodex's `google-antigravity` provider): Google's terms forbid it (its FAQ names Claude Code) and it has disabled accounts for it.

## When

1. **Main use: save Claude and Codex usage.** When a task is clear and simple to do (a specific code change, a mechanical edit across files, extraction, a summary, a first draft), give it to Gemini and keep the orchestrating agent for planning and checking.
2. **Lower priority, still use:** a second-opinion review by a different model family, and video or audio understanding.

## Model and effort

Run `agy models` at the start of the task and use the newest model generation offered. Ids end in the effort level (`-low`, `-medium`, `-high`).

- **Easy or quick tasks:** the newest Flash.
- **Hard tasks:** the newest Pro, but only if its version is at least as new as the newest Flash; otherwise the newest Flash.
- **Effort:** `-medium` for routine work, `-high` when the task needs more reasoning. Avoid `-low` unless the job is trivial and bulk.
- A model or effort the user names wins over all of this.

As of 2026-09-29 the newest Flash is 3.8 and the newest Pro is 3.1 (older), so the default for both easy and hard tasks is `gemini-3.8-flash-medium` or `gemini-3.8-flash-high`.

Always tell the user which model id Gemini ran on. The JSON result doesn't include it, so record the `--model` you passed (in `PLAN.md` for multi-call runs).

## Call

Run from the project folder (agy reads its `AGENTS.md`; plugin rules don't reach it, so state any rule that matters in the prompt):

```bash
agy -p "<self-contained task>" --model gemini-3.8-flash-medium --output-format json --print-timeout 10m > "$RUN/<job>.json"
```

- Permissions: the default is read-only (writes and shell are auto-denied and listed in `denied_actions`). `--mode accept-edits` also allows file edits, still no shell. Never pass `--dangerously-skip-permissions`. For code changes, prefer asking for a patch and applying it yourself.
- Result: read `.response`; check `.status` and `.denied_actions`. Continue the same thread with `--conversation <conversation_id>`.
- Codex: its sandbox blocks network access, so request approval to run `agy` outside the sandbox.
- Not installed: `agy` is Google's Antigravity CLI; ask the user to install it from Google's Antigravity site rather than installing it yourself.
- `authentication required`: the user must run `agy` once in a terminal to sign in; it can't be done headless.

## Use as few calls as the work needs

Gemini usage is limited. Use the smallest number of parallel calls that gets the work done: one call when one will do, two or three when the work splits cleanly, rarely more. Never fan out dozens of calls. Batch small related items into one call instead of one call each, and prefer continuing a thread (`--conversation`) over starting a new one.

## Resume when usage runs out

Any job with more than one call, or one that edits files, keeps a run folder so another session can pick it up:

- `RUN=~/.gemini-runs/<project>-<YYYY-MM-DD>-<short-task>`, created before the first call. It stays on this Mac only.
- `PLAN.md` there: the goal, the model used, and one line per job with its status (`todo`, `running`, `done`, `failed: <reason>`), its `conversation_id`, and the files it touches. Update it after every call.
- Save each call's JSON to `$RUN/<job>.json`.

If a call fails on quota or rate limits, stop starting new calls, mark the job `failed: quota` in `PLAN.md`, and tell the user what is done and what is left. To continue later (or from a new session): read `PLAN.md`, check the listed files and `git status` for partial edits, then rerun the unfinished jobs, resuming with `--conversation <id>` where one exists. If the work is urgent, the orchestrating agent may finish the remaining jobs itself. Delete the run folder once everything is done and checked.

## After

Gemini's answer is another model's opinion: check its claims and edits against the files before acting, and tell the user which parts came from Gemini and on which model.
