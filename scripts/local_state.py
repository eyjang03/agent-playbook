"""Small, locked local state files shared by both apps (Python 3.9+)."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import tempfile
import time


def directory():
    return Path(os.environ.get("AGENT_PLAYBOOK_HOME", Path.home() / ".agent-playbook"))


@contextmanager
def lock(name, wait=2):
    folder = directory()
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    with open(folder / (name + ".lock"), "a+b") as handle:
        if os.name == "nt":
            import msvcrt
            handle.write(b"0")
            handle.flush()
            def acquire():
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            def release():
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            def acquire():
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            def release():
                fcntl.flock(handle, fcntl.LOCK_UN)
        until = time.monotonic() + wait
        while True:
            try:
                acquire()
                break
            except OSError:
                if time.monotonic() >= until:
                    raise RuntimeError("Another playbook operation is running; try again shortly.")
                time.sleep(0.05)
        try:
            yield
        finally:
            release()


def read(name):
    path = directory() / name
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("Invalid local state; inspect it before continuing.")
    return data


def update(name, change):
    with lock(name):
        data = read(name)
        change(data)
        fd, path = tempfile.mkstemp(prefix=name + ".", dir=directory())
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(data, handle, indent=2)
                handle.write("\n")
            os.replace(path, directory() / name)
        finally:
            if os.path.exists(path):
                os.unlink(path)
