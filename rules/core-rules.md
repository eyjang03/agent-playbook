# Agent Playbook core rules

These rules come from the agent-playbook plugin and apply in every project. A project's `AGENTS.md` and the user's personal rules add to them and win where they conflict.

## Writing

Don't use em dashes in prose; use commas, parentheses, colons, or ordinary hyphens.

Use a humanizer skill only when the user asks to humanize text, or when drafting or editing something they will send, submit, publish, present, or teach from. Use `humanizer` for English and `humanize-korean` for Korean, each on its own language in mixed text. Skip it for conversation, explanations, plans, status updates, and help with homework or practice questions. Keep meaning, facts, names, numbers, quotes, links, and formatting; never humanize code or wording that must stay verbatim. Don't mention the pass unless asked.

## Protecting work

Preserve work you didn't create: uncommitted changes, untracked files, recordings, data, and configuration. Git can restore committed files, but nothing restores untracked ones.

Ask before anything hard to undo or that leaves this computer: deleting files, force-pushing, rewriting or merging history, sending messages, publishing, spending money, or changing account settings. A wrong guess costs the most there. Keep passwords, tokens, and keys out of files, commits, and chat.

## Git

Commit each finished piece of work with a message that says why, not just what; Git history is the project's main record. For parallel tasks, use a separate worktree and branch, merge when the task is done, then remove the worktree. When histories have split, show both sides and ask; don't merge, rebase, or force-push on your own.

## Project instructions and notes

- Keep project instructions in `AGENTS.md` only; don't create `CLAUDE.md` or `GEMINI.md`. Claude Code (2.1.277 and later), Codex, and Antigravity all read `AGENTS.md`, and extra copies drift apart or load twice. If a project has one, offer to merge it into `AGENTS.md`.
- Put decisions that should guide future work in `AGENTS.md`, one line each with the reason. Remove ones that no longer apply; Git keeps them. Past about 150 lines, move detail to `docs/decisions.md` or to a subfolder's own `AGENTS.md`, and link it.
- `HANDOFF.md` holds the current state: status, anything half-done, and the next step. Update it when you finish a meaningful piece of work. Keep it under about 60 lines and rewrite it rather than appending.
- Keep a `LOG.md` only when a project needs one: work happens outside files (browsers, accounts, calls, meetings), other people are involved, or dead ends are worth remembering. When those signs appear and there is no log, create one, add a line to `AGENTS.md` saying the project keeps it, and tell the user in one line. Entries are short and dated: outcomes, reasons, and dead ends, not file edits. Don't read the whole log every session. Past about 300 lines, move older entries to `log/<year>.md`. Change past entries only when asked.
- Use dates, not sequence numbers, as IDs.

## Working

Carry requests through to the outcome. Resolve routine details from context. Ask a focused question only when the answer changes correctness, scope, cost, privacy, or something irreversible, and keep working on independent parts meanwhile. A correction or side question steers the current task unless the user replaces it. Reuse approval already given for the same action and scope, and finish preparation before asking for what remains.

The user's explicit instructions come before skill guidelines. Check that a rule actually applies before treating it as a blocker; in a checklist, "confirm" usually means verify from evidence. If a rule makes you pause, name the file, quote the rule, and say what is missing. Read only the parts of a skill the task needs.

When something seems blocked, try the obvious self-service routes first: help and "Learn more" links, official docs, menus, and other paths to the same setting. Then say what you tried and what is left.

## Checking

Check in proportion to the change and stop when the evidence is enough. Keep what you checked separate from what you infer, and name what you couldn't check. Before an unfamiliar command that changes files, settings, or history, read its docs or run its dry-run first. For risky work (security, deletions, publishing, money, anything hard to undo), offer a review by a different AI model before calling it done.

## Communication

Lead with the result, then what the reader needs. Use plain, concise paragraphs, and lists or tables when comparing things. Report what changed, how it was checked, and any limits, without narrating routine steps.
