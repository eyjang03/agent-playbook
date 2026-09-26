---
name: project-notes
description: Sets up or tidies a project's instruction and note files the agent-playbook way (one AGENTS.md, a short HANDOFF.md, and a LOG.md only when the project needs one). Use when starting a new project, when a project has CLAUDE.md or GEMINI.md files, when AGENTS.md or notes have grown too long, or when the user asks to set up or review project notes.
---

# Project notes

The goal is a project any AI app, on any computer, can pick up quickly and cheaply:

| File | Holds | Read |
|---|---|---|
| `AGENTS.md` | project rules and decisions still in force, one line each with the reason | every session (automatically) |
| `HANDOFF.md` | current status, anything half-done, next step | every session (the playbook shows it) |
| `LOG.md` | outcomes, reasons, dead ends, work done outside files | only when history matters |
| Git history | what changed in files, and why (commit messages) | when needed |

## Set up or review a project

Look first, then propose all changes together and apply them after the user agrees.

1. **One instruction file.** If `CLAUDE.md` or `GEMINI.md` exists (at the root or in subfolders), compare it with `AGENTS.md`. Identical or pointer-only files can simply be deleted. If they differ, merge the unique content into `AGENTS.md`, putting app-specific notes under a heading like "Claude only", show the merged result, and delete the extra file only after approval. Claude Code 2.1.277 and later, Codex, and Antigravity all read `AGENTS.md`.
2. **Right-sized `AGENTS.md`.** If it has no project description, add two or three lines on what the project is. If it passes about 150 lines, move detail into `docs/decisions.md` or a subfolder's `AGENTS.md` and link it. Remove rules and decisions that no longer apply.
3. **`HANDOFF.md`.** Create it if missing. If it is long, stale, or full of old process notes, rewrite it to the current state in under about 60 lines.
4. **`LOG.md`: only if needed.** Recommend one when work happens outside files (browsers, accounts, calls, meetings), other people are involved, or research and dead ends are worth remembering. Otherwise say Git and the handoff are enough. For an existing oversized or process-heavy log, offer to move it to `archive/` rather than delete it.
5. **Commit** the changes with a message that says why.

## Keep in mind

- Ask before deleting or rewriting anything the user wrote. Archive instead of delete when unsure.
- Old logs, findings files, and audit trails from earlier systems are history: move them to `archive/`, don't leave them where every session reads them.
- Use dates, not sequence numbers, as IDs in logs and decisions.
