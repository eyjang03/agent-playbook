"""Embedded by build_hooks.py; runs only the runtime carried by an approved hook.

Do not launch this template directly. The generated command contains the archive,
so even its first invocation works after the installed plugin has been removed.
"""
import base64
import hashlib
import io
import json
from pathlib import Path
import runpy
import sys
import tempfile
import zipfile

ARCHIVE_B64 = "__ARCHIVE_B64__"
ARCHIVE_SHA256 = "__ARCHIVE_SHA256__"
FILES = (
    "scripts/playbook.py", "scripts/project.py", "scripts/local_state.py",
    "rules/core-rules.md", ".codex-plugin/plugin.json",
)


def failure(app, action):
    message = ("Agent Playbook could not run its bundled hook runtime. "
               "This hook did not complete; rules, context, or project sync may be missing. "
               "Reinstall the plugin and reload the session, then check playbook status.")
    output = {"systemMessage": message}
    if action in ("rules", "context"):
        output["hookSpecificOutput"] = {
            "hookEventName": "SessionStart", "additionalContext": message}
    print(json.dumps(output))


def main():
    app, action = (sys.argv[1:] + ["", ""])[:2]
    try:
        if len(sys.argv) != 3 or app not in ("codex", "claude") or action not in ("rules", "context", "stop"):
            raise ValueError("Invalid hook arguments")
        archive = base64.b64decode(ARCHIVE_B64, validate=True)
        if hashlib.sha256(archive).hexdigest() != ARCHIVE_SHA256:
            raise ValueError("Hook archive checksum mismatch")
        # A private, per-invocation directory avoids shared runtime races and stale
        # files. No installed cache, current-version link, or network is consulted.
        with tempfile.TemporaryDirectory(prefix="agent-playbook-hook-") as folder:
            root = Path(folder)
            with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
                if sorted(bundle.namelist()) != sorted(FILES):
                    raise ValueError("Unexpected hook archive contents")
                for name in FILES:
                    target = root / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(bundle.read(name))
            scripts = root / "scripts"
            sys.path.insert(0, str(scripts))
            if action == "stop":
                sys.argv = [str(scripts / "project.py"), "hook", "end", "--app", app]
            else:
                sys.argv = [str(scripts / "playbook.py"), "start", "--app", app, "--part", action]
            runpy.run_path(sys.argv[0], run_name="__main__")
    except SystemExit as exc:
        if exc.code not in (None, 0):
            failure(app, action)
    except Exception:
        # Keep exceptions/paths out of the feedback and do not trigger stop retries.
        # A warning is deliberately different from a successful empty hook result.
        failure(app, action)


if __name__ == "__main__":
    main()
