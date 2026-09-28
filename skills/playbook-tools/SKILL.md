---
name: playbook-tools
description: Installs and checks the agent-playbook's recommended tools (humanizer, humanize-korean, ponytail, hyperframes video skills, frontend-design, web-design-guidelines) in Claude Code and Codex, and checks that the playbook itself is running. Use when the user says "install the playbook tools", sets up a new computer, or asks whether their tools or the playbook are working.
---

# Playbook tools

## 1. Is the playbook running?

Run `python3 scripts/playbook.py status` from this plugin's folder. Each app the user has should show a recent `rules` and `context` run. If an app shows "never ran": in Codex, the plugin's hooks probably still need approving; in Claude Code, check that the plugin is installed and enabled (`claude plugin list`).

## 2. Tools

1. Read `tools/tools.md` in this plugin's folder.
2. For each tool and each app the user has, run the check and build a short table: installed, missing, or installed but switched off.
3. Ask which missing tools to install, per app. Mention what each is for in a few words; don't assume they want all of them.
4. Install the chosen ones with the listed commands, one tool at a time. If a command asks questions, answer from the table or ask the user. Don't install Node.js without asking.
5. Run the checks again and report the final table, including anything the user has to do themselves (signing in, approving Codex hooks, restarting an app).

Skip tools the user already gets another way, such as a synced or customized copy; installing a second copy makes it appear twice.
