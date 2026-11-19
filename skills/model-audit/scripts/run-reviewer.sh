#!/bin/bash
# Runs one audit reviewer inside its own macOS sandbox and collects its report only if the run completed.
# Usage: run-reviewer.sh <claude|codex|agy> <model id or alias> <effort, or - for agy> <reviewer dir> [grant ...]
# Grants as in mkprofile.sh: project:<git repo root>  runtime:<python>  file:<file>  hide:<path>
# Layout: <audit folder>/<round>/<reviewer>, the audit folder in a folder under /tmp (AUDIT_ROOT, default two levels up)
# and marked by an empty .audit-folder file that the orchestrator creates with it.
# A new round or revision always gets new reviewer folders. The first run keeps the prepared pack as pack-master
# (which the reviewer cannot write); every attempt starts from a fresh copy of it, and a retry whose prepared files
# were changed is refused. Each attempt gets an attempt-N folder (profile, pack manifest, project fingerprints, raw
# output, log, meta); report.md beside pack/ is replaced only by a collected report.
# Codex uses the Codex home in AUDIT_CODEX_HOME when it is set (for example a second account's), otherwise ~/.codex. AUDIT_TIMEOUT_MIN limits the run (default 240 minutes).
set -euo pipefail
{  # the whole script is one block, read in full before it runs, so editing the file cannot change a running copy
[ $# -ge 4 ] || { echo "usage: run-reviewer.sh <claude|codex|agy> <model> <effort|-> <reviewer dir> [grant ...]" >&2; exit 2; }
T=$1; M=$2; E=$3; shift 3; RIN=$1; shift
case $T in claude|codex|agy) ;; *) echo "unknown CLI: $T" >&2; exit 2 ;; esac

# validate the exact layout before anything is created, copied or removed
[ -d "$RIN" ] && [ ! -L "$RIN" ] || { echo "reviewer folder not found (or a link): $RIN" >&2; exit 2; }
R=$(cd "$RIN" && pwd -P)
AUD=$(cd "${AUDIT_ROOT:-$(dirname "$(dirname "$R")")}" && pwd -P); export AUDIT_ROOT=$AUD
case $AUD in /private/tmp/?*/?*|/private/tmp/audit-?*) ;; *) echo "audit folder must be inside a folder under /tmp: $AUD" >&2; exit 2 ;; esac
[ "$(dirname "$(dirname "$R")")" = "$AUD" ] || { echo "reviewer folder must be exactly <audit folder>/<round>/<reviewer>: $R" >&2; exit 2; }
# the orchestrator marks each audit folder when it creates it, so a mistyped path never reaches the copy and delete steps
[ -f "$AUD/.audit-folder" ] && [ ! -L "$AUD/.audit-folder" ] || { echo "not an audit folder (create it with an empty .audit-folder file): $AUD" >&2; exit 2; }
for d in "$R/pack" "$R/tmp" "$R/pack-master"; do [ ! -L "$d" ] || { echo "refusing a link at $d" >&2; exit 2; }; done
HERE=$(cd "$(dirname "$0")" && pwd -P)
case $HERE in "$AUD"|"$AUD"/*) echo "run the launcher from the master tools, not from inside the audit folder" >&2; exit 2 ;; esac
PYI=/usr/bin/python3                      # trusted interpreter for reading results, always run with -I from $A
"$PYI" -I -X utf8 -c pass 2>/dev/null || { echo "$PYI is unavailable (install Apple's Command Line Tools)" >&2; exit 2; }
TIMEOUT_MIN=${AUDIT_TIMEOUT_MIN:-240}
case $T in
  claude) BIN=${CLAUDE_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}; ST="$HOME/.claude"; ACCT=main ;;
  codex)  BIN=${CODEX_BIN:-$(command -v codex || echo /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex)}
          [ -x "$BIN" ] || { echo "CLI not found: $BIN" >&2; exit 2; }
          ST=${AUDIT_CODEX_HOME:-$HOME/.codex}; ACCT="Codex home $ST"
          CODEX_HOME="$ST" "$BIN" login status >/dev/null 2>&1 || { echo "Codex is not signed in for $ST" >&2; exit 2; } ;;
  agy)    BIN=${AGY_BIN:-$(command -v agy || echo "$HOME/.local/bin/agy")}; ST="$HOME/.gemini"; ACCT=main ;;
esac
[ -x "$BIN" ] || { echo "CLI not found: $BIN" >&2; exit 2; }
RBIN=$("$PYI" -I -X utf8 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$BIN")
# grants in canonical form (real paths), so the same input always has the same identity across the round
CG=(); for g in "$@"; do k=${g%%:*}; v=${g#*:}
  if [ "$k" = runtime ] && [ -e "$v" ]; then   # keep the interpreter's own name: a venv's bin/python is a link to its base
    CG+=("$k:$("$PYI" -I -X utf8 -c 'import os,sys; print(os.path.join(os.path.realpath(os.path.dirname(sys.argv[1])), os.path.basename(sys.argv[1])))' "$v")")
  elif [ "$k" != "$g" ] && [ -e "$v" ]; then CG+=("$k:$("$PYI" -I -X utf8 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$v")"); else CG+=("$g"); fi; done
[ ${#CG[@]} -gt 0 ] && set -- "${CG[@]}"
INPUTS_PY="$HERE/inputs.py"; [ -f "$INPUTS_PY" ] || { echo "missing $INPUTS_PY" >&2; exit 2; }

# the first run freezes the prepared pack as pack-master, with a manifest the reviewer cannot write; every attempt
# starts from pack-master, so a reviewer's edits never carry over, and a pack-master that changed (an edited, added
# or removed file) is refused: a new revision needs new reviewer folders
manifest() { local m; m=$("$PYI" -I -X utf8 "$INPUTS_PY" pack "$@") && [ ${#m} -eq 64 ] || { echo "the pack could not be hashed: $1" >&2; exit 2; }; echo "$m"; }   # every entry: type, executable bit, contents
if [ -d "$R/pack-master" ]; then
  [ -f "$R/pack-master.sha256" ] && [ "$(manifest "$R/pack-master")" = "$(cat "$R/pack-master.sha256")" ] \
    || { echo "pack-master changed since the first run, or has no manifest: a new revision needs new reviewer folders" >&2; exit 2; }
else
  [ -f "$R/pack/PROMPT.md" ] || { echo "missing $R/pack/PROMPT.md" >&2; exit 2; }
  odd=$(find "$R/pack" ! -type f ! -type d 2>/dev/null | awk 'NR==1')
  [ -z "$odd" ] || { echo "the pack must hold only regular files and folders (no links or special files): $odd" >&2; exit 2; }
fi
mkdir -p "$R/tmp"; PROF=$(mktemp "$AUD/.profile.XXXXXX"); BX=$(mktemp "$AUD/.boxcheck.XXXXXX")
AUDIT_CLI_BIN=$RBIN "$HERE/mkprofile.sh" "$T" "$R" "$ST" "$@" > "$PROF" || { rm -f "$PROF" "$BX"; exit 2; }   # grants checked before anything is replaced
# the process scanner must work, or cleanup could not find a detached process (needs Apple's Command Line Tools)
/usr/bin/clang -O2 -o "$BX" "$HERE/boxcheck.c" 2>/dev/null && "$BX" "$R/tmp" "$AUD" "$(date +%s)" >/dev/null \
  || { rm -f "$PROF" "$BX"; echo "boxcheck could not be compiled or run (install Apple's Command Line Tools): refusing to start" >&2; exit 2; }
if [ ! -d "$R/pack-master" ]; then cp -Rp "$R/pack" "$R/pack-master"; manifest "$R/pack-master" > "$R/pack-master.sha256"; fi
chmod -R u+rwX "${R:?}/pack" "${R:?}/tmp" 2>/dev/null || true
rm -rf "${R:?}/pack" "${R:?}/tmp"; cp -Rp "$R/pack-master" "$R/pack"; mkdir "$R/tmp"
n=1; while [ -e "$R/attempt-$n" ]; do n=$((n+1)); done; A="$R/attempt-$n"; mkdir "$A"
rm -f "$R/report.md"; mv "$PROF" "$A/profile.sb"; mv "$BX" "$A/boxcheck"
( cd "$R/pack" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 stat -f '%Lp %N'; find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 ) > "$A/pack-manifest.txt"
printf 'cli=%s\nmodel_requested=%s\neffort_requested=%s\naccount=%s\nstate=%s\ncli_version=%s\nhost=%s\nstarted=%s\npack_manifest_sha256=%s\n' \
  "$T" "$M" "$E" "$ACCT" "$ST" "$("$BIN" --version 2>/dev/null | head -1)" "$(hostname -s)" "$(date '+%Y-%m-%d %H:%M:%S %z')" \
  "$(shasum -a 256 < "$A/pack-manifest.txt" | cut -d' ' -f1)" > "$A/meta.txt"
# the granted inputs, read as data: every tracked and untracked file of each project (Git only lists them, with
# fsmonitor, hooks and the untracked cache off, so no repository-configured program runs; contents are hashed
# directly, so diff drivers, filters and assume-unchanged flags play no part) and every file: grant (grant ignored
# data that matters this way). A missing or unreadable file changes the hash instead of stopping the launcher.
# The round's first reviewer records each fingerprint beside the reviewer folders; every reviewer of the round
# must match it before and after its run, so the whole panel reviews the same inputs.
gitq() { git -C "$1" -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.untrackedCache=false "${@:2}"; }
fingerprint() {   # $1 input, $2 per-file list to write: one hash, "listing-failed" or "incomplete"
  case $1 in
    project:*) local p=${1#project:} l; l=$(mktemp "$A/.list.XXXXXX")
      if gitq "$p" ls-files -z --cached --others --exclude-standard > "$l" 2>/dev/null; then
        "$PYI" -I -X utf8 "$INPUTS_PY" project "$p" "$(gitq "$p" rev-parse HEAD 2>/dev/null || echo none)" "$2" < "$l" 2>/dev/null | awk 'NR==1' || true
      else echo listing-failed; fi; rm -f "$l" ;;
    file:*) "$PYI" -I -X utf8 "$INPUTS_PY" file "${1#file:}" 2>/dev/null || echo incomplete ;;
  esac
}
roundcheck() {   # $1 name, $2 value: the round's first reviewer records it; every other reviewer must match
  local key="$(dirname "$R")/.round-$1" tf; tf=$(mktemp "$(dirname "$R")/.round-new.XXXXXX"); printf '%s\n' "$2" > "$tf"
  ln "$tf" "$key" 2>/dev/null || true; rm -f "$tf"; [ "$(cat "$key" 2>/dev/null)" = "$2" ]
}
INPUTS=(); for g in "$@"; do case $g in project:*|file:*) INPUTS+=("$g") ;; esac; done
for g in "${INPUTS[@]:-}"; do [ -n "$g" ] || continue
  case $g in project:*) echo "project=${g#project:} commit=$(gitq "${g#project:}" rev-parse HEAD 2>/dev/null || echo none)" >> "$A/meta.txt" ;; esac
  key=$(printf %s "$g" | shasum -a 256 | cut -c1-16); f=$(fingerprint "$g" "$A/input-$key.before.txt"); [ -n "$f" ] || f=incomplete
  case $f in listing-failed|incomplete) ;; *) [ -f "$A/input-$key.before.txt" ] && ln "$A/input-$key.before.txt" "$(dirname "$R")/.round-input-$key.list" 2>/dev/null || true ;; esac   # the first reviewer's file list
  printf 'input=%s fingerprint_before=%s\n' "$g" "$f" >> "$A/meta.txt"
  case $f in listing-failed|incomplete) echo "invalid=could not fingerprint $g ($f)" >> "$A/meta.txt" ;; esac
  case $f in listing-failed|incomplete) ;;   # a failure is never recorded as the round's value
    *) roundcheck "input-$key" "$f" || echo "invalid=this reviewer's inputs differ from the round's first reviewer's: $g (compare input-$key.before.txt with ../.round-input-$key.list)" >> "$A/meta.txt" ;; esac
done
# the whole panel gets the same grants and the same shared pack (only the prompt, the reviewer's own previous
# report and its capcheck.conf may differ)
roundcheck grants "$(printf '%s\n' "${CG[@]:-}" | LC_ALL=C sort)" || echo "invalid=this reviewer's grants differ from the round's first reviewer's" >> "$A/meta.txt"
roundcheck pack "$(manifest "$R/pack-master" PROMPT.md context/previous-own-report.md tools/capcheck.conf)" \
  || echo "invalid=this reviewer's shared pack files differ from the round's first reviewer's" >> "$A/meta.txt"

# inputs that already differ from the round's (or could not be fingerprinted) end the attempt before any CLI starts
if grep -q '^invalid=' "$A/meta.txt"; then
  echo "rejected=the inputs did not match the round before the start (see invalid=); the CLI was not started" >> "$A/meta.txt"
  echo "$T $M: not started: its inputs, grants or shared pack differ from the round's first reviewer's ($A)" >&2; exit 1
fi

# Claude renews an expired sign-in by writing the keychain, which the sandbox forbids (seen as
# "401 OAuth access token has expired"). Renew it first with one tiny request outside the sandbox, from an empty
# folder in safe mode (no hooks, plugins, MCP servers or tools), limited to two minutes.
if [ "$T" = claude ]; then
  SI=$(mktemp -d "$AUD/.signin.XXXXXX")
  ( cd "$SI" && env -i HOME="$HOME" USER="$USER" LANG="${LANG:-en_US.UTF-8}" PATH="/usr/bin:/bin" /usr/bin/perl -e 'alarm 120; exec @ARGV' \
      "$BIN" -p "Reply with OK." --model haiku --safe-mode --strict-mcp-config --no-session-persistence --tools "" --output-format json \
      < /dev/null > "$A/claude-signin.json" 2>&1 ) || true
  rm -rf "${SI:?}"
  "$PYI" -I -X utf8 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("is_error") is False else 1)' "$A/claude-signin.json" 2>/dev/null \
    || { echo "rejected=Claude could not sign in even outside the sandbox (see claude-signin.json)" >> "$A/meta.txt"
         echo "$T $M: Claude could not sign in even outside the sandbox; run claude once in a terminal on this Mac to sign in ($A)" >&2; exit 2; }
  "$PYI" -I -X utf8 - "$A/claude-signin.json" "$TIMEOUT_MIN" >> "$A/meta.txt" 2>/dev/null <<'PY' || true
import datetime, json, sys
e = json.load(open(sys.argv[1])).get("credential_expires_at")
if e:
    t = datetime.datetime.fromisoformat(e.replace("Z", "+00:00")); now = datetime.datetime.now(datetime.timezone.utc)
    if t < now + datetime.timedelta(minutes=int(sys.argv[2]) + 10):
        print("note=Claude's sign-in expires at %s, within this run's time limit; it cannot be renewed inside the sandbox, so a long run may fail with an expired sign-in" % e)
PY
fi

# clean environment: nothing inherited from the orchestrator (tokens, sockets, SSH agent)
ENVV=(HOME="$HOME" USER="$USER" LOGNAME="$USER" LANG="${LANG:-en_US.UTF-8}" TMPDIR="$R/tmp/" TMPPREFIX="$R/tmp/zsh"
      PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0 MPLCONFIGDIR="$R/tmp/matplotlib"
      IPYTHONDIR="$R/tmp/ipython" JUPYTER_RUNTIME_DIR="$R/tmp/jupyter-runtime" JUPYTER_DATA_DIR="$R/tmp/jupyter-data")
case $T in
  codex)  ENVV+=(CODEX_HOME="$ST")
          CMD=("$BIN" --search exec -m "$M" -c "model_reasoning_effort=\"$E\"" -c features.apps=false
               -s danger-full-access --ephemeral --ignore-user-config --ignore-rules --skip-git-repo-check
               -C "$R/pack" -o "$R/tmp/codex-final-message.md" -) ;;
  claude) ENVV+=(CLAUDE_CODE_TMPDIR="$R/tmp")
          CMD=("$BIN" -p --model "$M" --effort "$E" --safe-mode --strict-mcp-config --no-session-persistence
               --settings '{"sandbox":{"enabled":false}}' --output-format json
               --tools "Agent,Bash,Read,Write,Edit,NotebookEdit,WebFetch,WebSearch,Monitor,TaskStop,ToolSearch"
               --permission-mode bypassPermissions) ;;
  agy)    CMD=("$BIN" -p "Read the file $R/pack/PROMPT.md with your file tool and follow it exactly. Your working folder is $R/pack."
               --model "$M" --add-dir "$R/pack" --disable-slash-commands
               --settings '{"enableTerminalSandbox":false,"agentMode":"","permissions":{"allow":["command(*)","read_file(*)","write_file(*)","read_url(*)","download_url(*)"]}}'
               --output-format json --print-timeout "${TIMEOUT_MIN}m") ;;
esac

# agy's shell helper runs in later, unsandboxed agy sessions: written clean before every run (the sandbox allows
# only content changes to it) and checked afterwards; a link or any non-regular file is tampering, never followed
HELPER="$ST/antigravity-cli/bin/agentapi"
helper_text() { printf '#!/bin/sh\nexec "%s" agentapi "$@"\n' "$1"; }
helper_ok() { [ -f "$HELPER" ] && [ ! -L "$HELPER" ] && [ "$(stat -f %Lp "$HELPER")" = 755 ] &&
              { helper_text "$BIN" | cmp -s - "$HELPER" || helper_text "$RBIN" | cmp -s - "$HELPER"; }; }
helper_fix() { rm -f "$HELPER"; ( set -C; helper_text "$BIN" > "$HELPER" ); chmod 755 "$HELPER"; }
# conversations idle for an hour at launch (a concurrent agy session does not count): content hashes, and afterwards
# the same files hashed again, so any edit, removal or replacement shows (about 6 s each way for 600 MB)
history_hash() { "$PYI" -I -X utf8 "$INPUTS_PY" history "$ST/antigravity-cli/brain" "$ST/antigravity-cli/conversations" || echo incomplete; }
history_rehash() { "$PYI" -I -X utf8 "$INPUTS_PY" rehash "$1" || echo incomplete; }
if [ "$T" = agy ]; then
  mkdir -p "$(dirname "$HELPER")"
  if { [ -e "$HELPER" ] || [ -L "$HELPER" ]; } && ! helper_ok; then cp -P "$HELPER" "$A/agentapi.found-before" 2>/dev/null || true; echo "note=agy shell helper was changed before this run; restored" >> "$A/meta.txt"; fi
  helper_ok || helper_fix
  history_hash > "$A/agy-history.before"
  if grep -qx incomplete "$A/agy-history.before"; then echo "rejected=the agy history baseline did not finish" >> "$A/meta.txt"; echo "$T $M: not started: agy's history check did not finish ($A)" >&2; exit 1; fi
fi

# process ownership: the CLI's process group, every descendant recorded while it runs (pid and start time, so a
# reused pid is never signalled), and every process that boxcheck finds in this reviewer's sandbox (sandboxed,
# allowed to write this reviewer's tmp, not allowed to write the audit folder, started during this attempt).
# Nothing else is signalled, and every signalled process is logged with its command line.
started() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'; }
descendants() { local kids k st; kids=$(pgrep -P "$1" 2>/dev/null) || return 0
  for k in $kids; do st=$(started "$k"); [ -n "$st" ] && echo "$k $st"; descendants "$k"; done; }
# the reviewer's processes anywhere on this Mac, found by their sandbox (compiled per run; needs Command Line Tools)
START_EPOCH=$(date +%s)
holders() { { for d in "$R/pack" "$R/tmp"; do [ -d "$d" ] && [ ! -L "$d" ] && lsof -t +D "$d" 2>/dev/null; done; } | sort -u | grep -vx "$$" || true; }
owned() {   # live processes of this attempt, one pid per line
  { sort -u "$A/.seen" 2>/dev/null | while read -r sp st; do [ -n "$st" ] && [ "$(started "$sp")" = "$st" ] && echo "$sp"; done
    "$A/boxcheck" "$R/tmp" "$AUD" "$START_EPOCH" 2>/dev/null || echo failed >> "$A/.scan-failed"
  } | grep -vx "$$" | sort -u || true; }
CLEANED=
cleanup() {
  [ -n "$CLEANED" ] && return 0; CLEANED=yes; set +e; touch "$A/.done"   # stops the supervisor at once
  if [ -n "${pid:-}" ]; then descendants "$pid" >> "$A/.seen" || true; kill -KILL -- "-$pid" 2>/dev/null || true; fi
  for sp in $(owned); do
    echo "signalled=$sp $(ps -o command= -p "$sp" 2>/dev/null | cut -c1-120)" >> "$A/meta.txt"; kill -KILL "$sp" 2>/dev/null || true
  done
  if [ "$T" = agy ] && ! helper_ok; then
    cp -P "$HELPER" "$A/agentapi.after" 2>/dev/null || true; helper_fix 2>/dev/null || true
    if helper_ok; then echo "tampered=agy shell helper changed during the run; restored" >> "$A/meta.txt"
    else echo "tampered=agy shell helper changed during the run and could NOT be restored: do not start agy until $HELPER is fixed" >> "$A/meta.txt"
         echo "WARNING: agy's shell helper could not be restored; do not start agy until $HELPER is fixed" >&2; fi
  fi
  return 0
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP                 # an interrupted launcher still cleans up

# run in its own process group under one supervisor that records descendants and enforces the time limit
set +e
( cd "$R/pack" && exec /usr/bin/perl -e 'setpgrp(0, 0); exec { $ARGV[0] } @ARGV or die "exec: $!\n"' \
    env -i "${ENVV[@]}" sandbox-exec -f "$A/profile.sb" "${CMD[@]}" ) < "$R/pack/PROMPT.md" > "$A/out" 2> "$A/run.log" &
pid=$!
( exec >/dev/null 2>&1; end=$(( $(date +%s) + TIMEOUT_MIN * 60 ))
  while kill -0 "$pid" 2>/dev/null && [ ! -e "$A/.done" ]; do
    descendants "$pid" >> "$A/.seen"
    if [ "$(date +%s)" -ge "$end" ]; then
      echo "timeout=yes" >> "$A/meta.txt"; kill -TERM -- "-$pid"; sleep 30; [ -e "$A/.done" ] || kill -KILL -- "-$pid"; exit 0
    fi
    sleep 5
  done ) & dog=$!
wait "$pid"; rc=$?
touch "$A/.done"; wait "$dog" 2>/dev/null
cleanup; sleep 1
survivors=$(owned | tr '\n' ' ')
others=$(holders | tr '\n' ' ')
set -e
echo "exit=$rc" >> "$A/meta.txt"
[ -z "$survivors" ] || echo "tampered=processes of this run survived cleanup: $survivors" >> "$A/meta.txt"
[ ! -s "$A/.scan-failed" ] || echo "invalid=the process scan failed, so leftover processes could not be ruled out" >> "$A/meta.txt"
[ -z "${others// /}" ] || echo "note=other processes held files in the reviewer folder (not signalled): $others" >> "$A/meta.txt"
if [ "$T" = agy ]; then
  history_rehash "$A/agy-history.before" > "$A/agy-history.after"
  grep -qx incomplete "$A/agy-history.after" && echo "invalid=the agy history check did not finish" >> "$A/meta.txt"
  changed=$( { LC_ALL=C diff "$A/agy-history.before" "$A/agy-history.after" || true; } | sed -n 's/^> [0-9a-z]*  //p; s/^> incomplete$/(the check did not finish)/p' | awk 'NR<=5' | tr '\n' ' ')
  [ -z "$changed" ] || echo "tampered=agy conversations idle for an hour changed (by the reviewer, or a concurrent agy session resumed one): $changed" >> "$A/meta.txt"
fi
for g in "${INPUTS[@]:-}"; do [ -n "$g" ] || continue
  before=$(grep -F "input=$g fingerprint_before=" "$A/meta.txt" | awk 'NR==1' | sed 's/.*fingerprint_before=//'); key=$(printf %s "$g" | shasum -a 256 | cut -c1-16)
  after=$(fingerprint "$g" "$A/input-$key.after.txt") || after=unavailable
  echo "input=$g fingerprint_after=$after" >> "$A/meta.txt"
  [ "$before" = "$after" ] || echo "invalid=a granted input changed during the run, so the verdict is not bound to one revision: $g (changed files: diff input-$key.before.txt input-$key.after.txt)" >> "$A/meta.txt"
done
trap - EXIT

# validate from the attempt folder with an isolated interpreter; nothing from the reviewer's folder is imported,
# and Codex's message is opened without following links
cd "$A"
if "$PYI" -I -X utf8 - "$T" "$rc" "$R/tmp/codex-final-message.md" <<'PY' >> "$A/meta.txt" 2>&1; then
import json, os, re, signal, stat, sys
t, rc, codex_msg = sys.argv[1], int(sys.argv[2]), sys.argv[3]
def fail(msg): print("rejected=" + msg); sys.exit(1)
signal.signal(signal.SIGALRM, lambda *a: fail("collecting the result took too long")); signal.alarm(60)
def raw():   # the reviewer's text, written to response.md before any check, so a rejected run keeps it
    try:
        if t == "codex":
            fd = os.open(codex_msg, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK); st = os.fstat(fd)
            data = os.read(fd, min(st.st_size, 2_000_000)) if stat.S_ISREG(st.st_mode) else b""; os.close(fd); return data.decode("utf-8", "replace")
        d = json.load(open("out")); return (d.get("result") if t == "claude" else d.get("response")) or ""
    except Exception:
        return ""
open("response.md", "w").write(raw())
meta = open("meta.txt").read().splitlines()
if "timeout=yes" in meta: fail("time limit reached")
if any(l.startswith("tampered=") for l in meta): fail("something outside the reviewer's folder was changed (see tampered=)")
if any(l.startswith("invalid=") for l in meta): fail("the run could not be bound to the round's inputs or verified (see invalid=)")
if rc != 0: fail("CLI exit %d" % rc)
if t == "codex":
    try: fd = os.open(codex_msg, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as e: fail("no readable final message (%s)" % e.strerror)
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1 or st.st_size > 2_000_000: fail("final message is not a plain file")
    text = os.read(fd, st.st_size).decode("utf-8", "replace"); os.close(fd)
else:
    try: d = json.load(open("out"))
    except Exception as e: fail("output is not JSON (%s)" % e)
    if t == "claude":
        if d.get("is_error") or d.get("subtype") != "success": fail("Claude reported an error")
        text = d.get("result") or ""
        print("model_confirmed=" + ",".join(d.get("modelUsage", {})))
    else:
        if d.get("status") != "SUCCESS": fail("agy status %s" % d.get("status"))
        if d.get("denied_actions"): fail("agy denied actions %s" % d.get("denied_actions"))
        text = d.get("response") or ""
open("response.md", "w").write(text)                       # raw response, kept whatever the outcome
lines = [l for l in text.splitlines() if l.strip()]
if not lines or lines[0] not in ("VERDICT: READY", "VERDICT: REVISE"): fail("first line is not an exact verdict")
for h in ("## Required changes", "## Checks performed"):
    if not any(l.strip() == h for l in lines): fail("missing section " + h)
open("report.md", "w").write(text)
print("verdict=" + lines[0].split()[1])
print("status=collected; a READY counts only after the orchestrator confirms the essential checks")
PY
  cp "$A/report.md" "$R/report.md"
  v=$(grep '^verdict=' "$A/meta.txt" | cut -d= -f2); [ "$v" = READY ] && v="READY (provisional: confirm the essential checks)"
  echo "$T $M: $v ($ACCT; $A)"
  exit 0
else
  echo "$T $M: run not accepted: $(grep -E '^rejected=' "$A/meta.txt" | cut -d= -f2-) ($A)"; exit 1
fi
}
