# Working tips

These habits come from using Codex and Claude Code side by side across two computers. Pick the ones that suit you; they are not prerequisites or a copy of the author's personal setup.

## Two apps, one project

Open the same project folder in both apps on a computer. Keep project instructions in `AGENTS.md` and current status in a short `HANDOFF.md`, so switching apps does not mean explaining everything again. App memories can help, but put decisions the next session needs in project files.

Use the apps in sequence when they will edit the same files. For independent tasks, give each task its own worktree and branch. Integration still needs review; automatic sync does not merge task branches for you. Both apps can share personal preferences without sharing every app setting.

## Two computers

One private repository per selected project makes the destination and upload scope easier to see. Keep the main working folder on the project's chosen default branch if you use automatic sync. Respect a team's branch and review process when joining an existing repository.

Commit finished work in small pieces with a message that explains why. Before changing computers, check that those commits reached the remote. On the receiving computer, start a session and verify the download before continuing. An upload alone does not prove the other computer is ready.

Keep another backup for files Git does not track: recordings, large datasets, ignored personal files, and unfinished edits. Private GitHub repositories do not back up those files merely because they sit inside the project folder.

## Give the AI useful preferences

Tell it what work you do, your preferred language and level of detail, and which decisions need your input. A few specific rules are easier to follow than a long duplicate manual. Keep passwords and account secrets out of the rules file.

For a substantial task, ask for an ordered plan with clear checks. For consequential publication or permission changes, consider an independent review; it does not replace checking the result.

Ask it to finish the authorized work and report what was actually verified, what is inferred, and what remains pending. This is especially useful when a task spans two apps, two computers, or an external service.
