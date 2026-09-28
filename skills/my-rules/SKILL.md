---
name: my-rules
description: Writes or updates the user's personal rules file (~/.agent-playbook/personal.md), which the agent-playbook plugin loads into every Claude Code and Codex session on top of its core rules. Use when the user says "set up my rules", wants to add or change a personal preference for all their AI sessions, or asks what their personal rules say.
---

# My rules

The playbook loads two layers at the start of every session, in both apps:

1. **Core rules** from the plugin (protecting work, Git habits, project notes, checking, communication). The same for everyone who installs it.
2. **Personal rules** from `~/.agent-playbook/personal.md`. Only this person's facts and preferences.

This skill writes layer 2.

Both apps on the same computer use this one file. Set it up once and preserve any existing personal plugin's rules. Offer relevant habits from `docs/working-tips.md` in this plugin as optional examples, then record only the person's choices. Do not copy the author's accounts, devices, paths, or model preferences. Git upload permission belongs in the selected project's local setup, not in a blanket personal rule.

## Set up or update

1. Read the core rules (`rules/core-rules.md` in this plugin's folder) and the current `~/.agent-playbook/personal.md` if it exists, so nothing gets duplicated or contradicted.
2. Ask a few short questions, one topic at a time, and skip anything already answered:
   - **Setup:** which computers and AI apps they use, and how projects are organized.
   - **Work:** what they mostly use AI for (school, coding, a business, writing).
   - **Style:** language, tone, how much detail, formatting likes and dislikes.
   - **Boundaries:** things the AI should always ask about, or never do, beyond the core rules.
   - **Tools:** skills or apps they want used (or avoided) for certain tasks.
3. Draft the file: short sections, one line per rule, each with its reason when the reason isn't obvious. Aim for under 60 lines; every line is read at the start of every session.
4. Show the draft and obtain any missing approval before saving. An explicit request to add or remove a specific rule already authorizes that change; do not ask for the same permission twice. Mention that it takes effect from the next session in both apps.

## Good personal rules

- Facts the AI can't infer: "I study Nanotechnology Engineering at Waterloo" or "My clinic has two locations."
- Preferences with reasons: "Explain in simple words; English is my second language."
- No passwords, keys, account numbers, or private data about other people. This file is plain text on disk.
- Avoid repeating core rules. A specific user choice can override a Playbook default for that person; record the scope clearly. Host safety and permission requirements still apply. To change the default for everyone, edit the plugin instead.
