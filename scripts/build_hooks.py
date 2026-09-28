#!/usr/bin/env python3
"""Build reproducible, cache-independent hooks; --check detects stale bundles."""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import shlex
import zipfile

from hook_bootstrap import FILES

ROOT = Path(__file__).resolve().parents[1]
MAX_COMMAND_BYTES = 60_000  # Stay below macOS/Linux per-argument limits.


def bootstrap(root):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for name in FILES:
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100600 << 16
            bundle.writestr(info, (root / name).read_bytes(), compresslevel=9)
    data = buffer.getvalue()
    source = (root / "scripts/hook_bootstrap.py").read_text(encoding="utf-8")
    return source.replace("__ARCHIVE_B64__", base64.b64encode(data).decode("ascii")).replace(
        "__ARCHIVE_SHA256__", hashlib.sha256(data).hexdigest())


def documents(root=ROOT):
    source = bootstrap(root)
    outputs = {}
    for app, filename in (("codex", "codex-hooks.json"), ("claude", "hooks.json")):
        def hook(action):
            command = shlex.join(["python3", "-I", "-c", source, app, action])
            if len(command.encode("utf-8")) > MAX_COMMAND_BYTES:
                raise ValueError("Hook command exceeds the tested size budget")
            item = {"type": "command", "command": command, "timeout": 30 if action == "rules" else 120}
            if app == "codex" and action != "stop":
                item["additionalContextLimit"] = 8000
                if action == "rules":
                    item["statusMessage"] = "Loading agent playbook"
            return item
        doc = {"hooks": {"SessionStart": [{"hooks": [hook("rules"), hook("context")]}],
                         "Stop": [{"hooks": [hook("stop")]}]}}
        outputs[root / "hooks" / filename] = json.dumps(doc, indent=2) + "\n"
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify without changing files")
    args = parser.parse_args()
    stale = []
    for path, text in documents().items():
        if args.check:
            if not path.is_file() or path.read_text(encoding="utf-8") != text:
                stale.append(str(path.relative_to(ROOT)))
        else:
            path.write_text(text, encoding="utf-8")
    if stale:
        print("Stale hook bundles: " + ", ".join(stale) + ". Run python3 scripts/build_hooks.py.")
        return 1
    print("Hook bundles " + ("are current." if args.check else "generated."))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
