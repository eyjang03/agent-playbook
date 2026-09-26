---
name: setup-playbook
description: Guides a new Agent Playbook user through app installation checks, shared personal preferences, selected projects, and optional tools. Use when someone asks to set up Agent Playbook on this computer, including when they use both Codex and Claude Code.
---

# Set up Agent Playbook

Work from the person's existing answers. Finish what can be checked locally and report remaining app approvals or other-computer checks separately.

1. Identify this computer, the operating system, and which apps they want to use. Check Git and Python 3.9+. Check installed plugin versions before installing anything. Read this plugin's `README.md` for installation and update commands. Use the CLI's help if its interface differs. Missing apps or runtimes need the person's choice before installation; continue with the apps already available.
2. Install the plugin separately in each chosen app. Keep any existing marketplace and user settings. The public plugin needs no private invitation or GitHub login to download. Let the person review hook permissions in the app. Do not approve hooks on their behalf.
3. Use the `my-rules` skill once per computer. Both apps read the same `~/.agent-playbook/personal.md`. Preserve existing preferences or personal plugins instead of creating a duplicate set. Ask about their workflow, show the draft, and save the agreed rules. App installation remains separate from shared preferences.
4. Offer the working tips in `docs/working-tips.md`. Present only the relevant ones, explicitly as choices. Do not give them the author's accounts, folders, private configuration, or model preferences. Ask which habits fit and record only their accepted preferences.
5. Ask which exact project folders they want to set up. Use `project-setup` for each selected folder, one at a time. Installing the plugin does not enroll projects, create GitHub repositories, or authorize uploads. Core rules and the memory bridge still run globally in the apps where the plugin is enabled; project choices control Git automation, not global rule loading.
6. Offer `playbook-tools` after the essentials. Check what is already installed and ask which optional tools they want. No bundle-wide installation by default.
7. Have them start a new session in each chosen app and ask it to check the playbook. Run `python3 scripts/playbook.py status` from the installed plugin folder. Verify fresh `rules` and `context` entries for each app, including the version. Old entries and a direct script test do not prove an app's hooks fired. Run `python3 scripts/playbook.py test` and `python3 -m unittest discover -s tests` for local code checks. Record unverified apps as pending instead of claiming success.

Report a short result: computer checked, apps verified, shared rules saved, projects selected and each upload/download choice, optional tools installed, and anything the person still needs to do. Show the update instructions from the README.

On another computer, repeat app installation and project selection there. Offer to copy their approved personal rules through a method they choose. Never assume a file, setting, or commit arrived because it was sent or uploaded elsewhere.
