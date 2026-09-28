# Hooks that survive plugin updates

Before 1.2.2, hook commands launched Python from the installed plugin directory.
An active Codex chat could retain that command after an update deleted the old
directory. The next stop hook failed before any Playbook code could run, and the
host repeatedly returned the error to the chat. Both hook manifests used this
pattern, so the fix covers both apps.

Since 1.2.3 there is no Stop hook at all. Python exits with code 2 when its
script is missing, and both hosts treat exit 2 from a Stop hook as "keep going",
so one stale path became an endless loop that used up a whole usage allowance.
Enrolled projects now upload pending commits at the next session start.

## Runtime carried by the command

`scripts/build_hooks.py` generates both hook manifests. Each command contains a
compressed archive of the three runtime modules, core rules, and version
manifest, plus the readable launcher in `scripts/hook_bootstrap.py`.

The launcher verifies the archive checksum, writes only the five allowlisted
files into a private temporary directory, and runs the requested entry point.
The directory stays alive for that invocation and is removed afterward. There
is no shared mutable runtime, lookup of a newer plugin, or dependency on the
installed directory. This also works if the directory disappeared before the
first invocation. Updates and concurrent apps cannot change an old command's
runtime.

Python runs in isolated mode (`-I`). Project files and `PYTHONPATH` cannot shadow
the launcher's standard-library imports. The runtime still reads personal rules,
memory, handoffs, and project permissions from their existing locations. This
change does not enroll projects, broaden upload permission, alter hook approval,
or add a background service. A selected project's sync actually runs after a
cache deletion; a successful return is not used as a substitute for that work.

The tradeoff is larger generated manifests: each hook command is approximately
23 KB with the current runtime. The builder enforces a 60 KB limit per command.
Source files remain the reviewable source of truth. Do not edit the encoded
payloads by hand. On a runtime, rules, or version change, run:

```sh
python3 scripts/build_hooks.py
python3 scripts/build_hooks.py --check
python3 scripts/playbook.py test
python3 -m unittest discover -s tests
```

The tests invoke the generated shell commands, delete the entire old plugin
directory, check both apps' rules/context output, verify real uploads to a local
bare Git repository, exercise concurrent calls, and check malformed bundles.
They also compare committed manifests with the builder's output. Generated
archives have fixed timestamps and file metadata. No personal files are bundled.

## Updates, approval, and existing sessions

Each changed runtime changes the hook command. Codex may require renewed hook
approval. Users must review it themselves; do not copy trust hashes or bypass the
app's approval flow. New sessions use the new approved hook definition. Existing
sessions retain the definition they already loaded, including its runtime.

This release cannot replace a command already cached by a pre-1.2.2 session.
After the first upgrade to 1.2.2, reload those sessions once. Keep the prior
version available until they close if a reload is not possible. Once a session
has loaded these self-contained hooks, removing its installed plugin version
does not break their execution.

The guarantee covers missing or replaced plugin cache files. It does not cover
an unavailable Python installation, exhausted temporary storage, forced process
termination, or host changes to hook protocols or command-size limits. Runtime
startup failures produce an explicit warning with a successful process exit so
the host does not retry a failing hook. They are never recorded as a
successful rules/context run. Existing project-sync failures retain their own
status and messages. A host that refuses to execute a hook still requires action
in that host.

## Platform verification

Shell execution and isolated integration tests are checked on macOS using Python
3.9 or later, `/bin/sh`, and zsh where available. The generated hooks use the same
shell-command interface in both manifests. A passing shell test is not proof of
hook approval or startup execution in a running app. Check fresh versioned status
records after installing in each app and on each computer.

## Upstream references

- [Codex hooks](https://developers.openai.com/codex/hooks): plugin hook trust and execution.
- [Claude plugin paths](https://code.claude.com/docs/en/plugins-reference#environment-variables): installed roots can change during updates; persistent data is separate.
