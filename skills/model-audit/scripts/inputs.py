"""Hashes audit inputs as data for run-reviewer.sh (run with /usr/bin/python3 -I, outside the sandbox).

Nothing is followed, executed or allowed to block: files are opened with O_NOFOLLOW and O_NONBLOCK, only regular
files are read, links are recorded by their target, other file types by their type, and every mode has a deadline.

  inputs.py project <root> <head> [list]   NUL-separated relative paths on stdin (git ls-files); prints one hash
                                    (and writes one line per file to <list>, to name what changed)
  inputs.py file <path>             prints one hash
  inputs.py pack <dir> [skip ...]   a pack folder (relative paths in skip are left out); prints one hash
  inputs.py history <dir> ...       "<sha256>  <path>" for each regular file idle for an hour
  inputs.py rehash <listing>        the same files again, in the same format ("unsafe" or "missing" instead of a hash)

Exit 4 (and the word "incomplete") when the deadline is reached; exit 2 on bad usage.
"""
import hashlib, os, signal, stat, sys, time


def deadline(seconds):
    def stop(*_):
        sys.stdout.write("incomplete\n"); sys.stdout.flush(); os._exit(4)
    signal.signal(signal.SIGALRM, stop); signal.alarm(seconds)


def entry(path):
    """One line describing a path without following it: type, executable bit, and content hash or link target."""
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return "missing"
    except OSError as e:
        return "unreadable %s" % e.errno
    if stat.S_ISLNK(st.st_mode):
        try:
            return "link %s" % os.readlink(path)
        except OSError as e:
            return "link unreadable %s" % e.errno
    if not stat.S_ISREG(st.st_mode):
        return "dir" if stat.S_ISDIR(st.st_mode) else "special %o" % stat.S_IFMT(st.st_mode)
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as e:
        return "unreadable %s" % e.errno
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return "special (replaced while opening)"
        h = hashlib.sha256()
        while True:
            b = os.read(fd, 1 << 20)
            if not b:
                break
            h.update(b)
        return "file %s %s" % ("x" if st.st_mode & 0o111 else "-", h.hexdigest())
    finally:
        os.close(fd)


def walk(top, skip_git=True, folders=False):
    """Every path under top, sorted, without following links; .git is skipped unless skip_git is False;
    folders are listed too when folders is True (so an empty folder counts)."""
    out = []
    for root, dirs, files in os.walk(top, followlinks=False):
        dirs[:] = sorted(d for d in dirs if not (skip_git and d == ".git"))
        for name in dirs:
            p = os.path.join(root, name)
            if folders or os.path.islink(p):
                out.append(p)
        out.extend(os.path.join(root, f) for f in files)
    return sorted(out)


def esc(p):   # one line per path, whatever its name holds
    return p.replace("\\", "\\\\").replace("\n", "\\n")


def unesc(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            out.append("\n" if s[i + 1] == "n" else s[i + 1]); i += 2
        else:
            out.append(s[i]); i += 1
    return "".join(out)


def digest(lines):
    h = hashlib.sha256()
    for line in lines:
        h.update(line.encode("utf-8", "surrogateescape") + b"\n")
    return h.hexdigest()


def main(argv):
    if len(argv) < 2:
        return 2
    mode = argv[1]
    if mode == "project" and len(argv) in (4, 5):
        deadline(900)
        os.chdir(argv[2])
        names = sorted(set(n for n in sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\0") if n))
        lines = ["head " + argv[3]]
        for n in names:
            e = entry(n)
            lines.append("%s %s" % (n, e))
            if e == "dir":   # an untracked nested repository: its files, without its .git
                lines.extend("%s %s" % (p, entry(p)) for p in walk(n))
        if len(argv) == 5:
            with open(argv[4], "w", encoding="utf-8", errors="surrogateescape") as f:
                f.write("\n".join(lines) + "\n")
        print(digest(lines))
    elif mode == "file" and len(argv) == 3:
        deadline(300)
        print(digest([entry(argv[2])]))
    elif mode == "pack" and len(argv) >= 3:
        deadline(300)
        os.chdir(argv[2])
        skip = set(argv[3:])
        print(digest("%s %s" % (p, entry(p)) for p in walk(".", skip_git=False, folders=True) if p[2:] not in skip))
    elif mode == "history":
        deadline(300)
        old = time.time() - 3600
        for top in argv[2:]:
            if not os.path.isdir(top) or os.path.islink(top):
                continue
            for p in walk(os.path.realpath(top), skip_git=False):   # real paths, so the re-hash can tell when a folder became a link
                try:
                    st = os.lstat(p)
                except OSError:
                    continue
                if stat.S_ISREG(st.st_mode) and st.st_mtime < old:
                    e = entry(p)
                    print("%s  %s" % (e.split()[-1] if e.startswith("file ") else "unsafe", esc(p)))
    elif mode == "rehash" and len(argv) == 3:
        deadline(300)
        for line in open(argv[2], encoding="utf-8", errors="surrogateescape"):
            line = line.rstrip("\n")
            if line == "incomplete":   # the baseline itself did not finish: nothing can be compared
                print("incomplete"); return 4
            if "  " not in line:
                print(line); continue
            p = unesc(line.split("  ", 1)[1])
            if os.path.realpath(p) != p:   # a folder on the way was replaced by a link
                print("unsafe  " + esc(p)); continue
            e = entry(p)
            print("%s  %s" % (e.split()[-1] if e.startswith("file ") else ("missing" if e == "missing" else "unsafe"), esc(p)))
    else:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
