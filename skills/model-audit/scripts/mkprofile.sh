#!/bin/bash
# Prints a sandbox-exec profile for one audit reviewer.
# Usage: AUDIT_ROOT=<audit folder> mkprofile.sh <claude|codex|agy> <reviewer dir> <CLI state dir> [grant ...]
# Layout: <audit folder>/<round>/<reviewer>/{pack,tmp}, the audit folder inside a folder under /tmp.
# Grants: project:<git repository root>  runtime:<python executable>  file:<file>  hide:<file or folder>
#   project  the whole repository, read-only (never one that holds another project, a CLI login or the audit folder)
#   runtime  the interpreter's environment and its base installation, read-only (read from pyvenv.cfg; nothing is run)
#   file     one file, read-only
#   hide     unreadable even inside a granted project (for example this audit's own records)
set -euo pipefail
[ $# -ge 3 ] || { echo "usage: AUDIT_ROOT=<dir> mkprofile.sh <claude|codex|agy> <reviewer dir> <state dir> [grant ...]" >&2; exit 2; }
T=$1
case $T in claude|codex|agy) ;; *) echo "unknown CLI: $T" >&2; exit 2 ;; esac
R=$(cd "$2" && pwd -P); ST=$(cd "$3" && pwd -P); H=$(cd "$HOME" && pwd -P); shift 3
AUD=$(cd "${AUDIT_ROOT:?set AUDIT_ROOT to the audit folder}" && pwd -P)
case $AUD in /private/tmp/?*/?*|/private/tmp/audit-?*) ;; *) echo "audit folder must be inside a folder under /tmp: $AUD" >&2; exit 2 ;; esac
[ "$(dirname "$(dirname "$R")")" = "$AUD" ] || { echo "reviewer folder must be exactly <audit folder>/<round>/<reviewer>: $R" >&2; exit 2; }
[ -d "$R/pack" ] && [ -d "$R/tmp" ] || { echo "missing $R/pack or $R/tmp" >&2; exit 2; }
q() { local s=${1//\\/\\\\}; printf '"%s"' "${s//\"/\\\"}"; }        # quote a path for the profile
rx() { printf %s "$1" | sed 's#[]*.^$()+?{}|\\[]#\\&#g; s#"#\\"#g'; }           # escape a path for a regex
UT=$(cd "$(getconf DARWIN_USER_TEMP_DIR)" && pwd -P); UC=$(cd "$(getconf DARWIN_USER_CACHE_DIR)" && pwd -P); UD=$(dirname "$UT")
real() {   # settings are compared as real paths; a relative or "~" entry would be silently meaningless, so it is refused
  case $1 in /*) ;; *) echo "audit settings need absolute paths: $1" >&2; exit 2 ;; esac
  [ -e "$1" ] || echo "note: an audit setting names a folder that does not exist: $1" >&2
  /usr/bin/python3 -I -X utf8 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
# AUDIT_PRIVATE: folders closed from every side, whatever the grant (CLI sign-in homes such as a second account's Codex
# home, whichever account a run uses). AUDIT_PROTECTED: collections, such as a folder of projects: the folder itself and
# anything above it cannot be granted, while single projects inside it can.
PRIVATE=("$(/usr/bin/python3 -I -X utf8 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$H/.codex")")
if [ -n "${AUDIT_CODEX_HOME:-}" ]; then r=$(real "$AUDIT_CODEX_HOME") || exit 2; PRIVATE+=("$r"); fi
IFS=: read -ra EXTRA <<< "${AUDIT_PRIVATE:-}"; for a in "${EXTRA[@]:-}"; do [ -n "$a" ] || continue; r=$(real "$a") || exit 2; PRIVATE+=("$r"); done
PROTECTED=("$H" /Users /Volumes "$AUD" "$ST" "$UT" "$UC" "$H/Documents" "$H/Desktop" "$H/Downloads")
IFS=: read -ra EXTRA <<< "${AUDIT_PROTECTED:-}"; for a in "${EXTRA[@]:-}"; do [ -n "$a" ] || continue; r=$(real "$a") || exit 2; PROTECTED+=("$r"); done

above() { [ "$1" = / ] || case $2 in "$1"|"$1"/*) true ;; *) false ;; esac; }   # is $1 equal to or above $2?
risky() {  # never readable as a grant: home, other users, the audit folder, CLI state and logins, temp folders, ~/Library
  local a                        # $2 = conda: a conda base may sit directly in home; every other rule still applies
  for a in "${PROTECTED[@]}" "${PRIVATE[@]}"; do above "$1" "$a" && return 0; done
  for a in "$AUD" "$H/Library" "$H/.ssh" "$H/.aws" "$H/.gnupg" "$H/.config" "$H/.claude" "$H/.codex" "$H/.gemini" "$H/.agents" "${PRIVATE[@]}" "$ST" "$UT" "$UC"; do
    above "$a" "$1" && return 0
  done
  [ "${2:-}" != conda ] && [ "$(dirname "$1")" = "$H" ] && return 0   # loose files and folders directly in home (~/.zshrc, ~/Pictures)
  return 1
}
READ=""; HIDE=""; PROJECTS=(); CONDA_HIDE=""; CONDA_ENVS=""
# Python installations a project environment may point to inside the home folder (read as data, never executed)
CONDA_ROOTS=("$H/miniconda3" "$H/miniforge3" "$H/anaconda3" "$H/.conda")
pyroot() {  # print the installation root to grant for an interpreter's prefix (the folder above its bin), or nothing;
  # with "auto" (an environment found in a project), only known installers in home are granted, never other places
  local b=$1 mode=${2:-explicit} r rest
  case $b in
    "$H"/*)
      for r in "$H/.local/share/uv/python" "$H/.pyenv/versions" "$H/.asdf/installs/python" "$H/.local/share/mise/installs/python"; do
        case $b in "$r"/*) rest=${b#"$r"/}; echo "$r/${rest%%/*}"; return 0 ;; esac
      done
      for r in "${CONDA_ROOTS[@]}"; do   # one conda environment only, or the base installation (its envs folder stays hidden)
        case $b in "$r"/envs/*) rest=${b#"$r"/envs/}; echo "$r/envs/${rest%%/*}"; return 0 ;; "$r"|"$r"/*) echo "$r"; return 0 ;; esac
      done
      echo "skipping an interpreter outside known Python installers: $b" >&2 ;;
    /private/tmp/*|/tmp/*|/Users/*|/Volumes/*|/private/var/folders/*)   # closed by the profile
      if [ "$mode" = explicit ]; then echo "$b"; else echo "skipping an environment base outside known installers (grant it as runtime: if needed): $b" >&2; fi ;;
    *) ;;   # /opt/homebrew, /Library, /usr, /Applications: readable already
  esac
}
is_conda_root() { local r; for r in "${CONDA_ROOTS[@]}"; do [ "$1" = "$r" ] && return 0; done; return 1; }
base_ok() { if is_conda_root "$1"; then ! risky "$1" conda; else ! risky "$1"; fi; }   # a conda base may sit directly in home
grant_base() {  # grant an installation root; a conda base keeps its environments hidden unless one is granted itself
  local r; READ+=" (subpath $(q "$1"))"
  is_conda_root "$1" && CONDA_HIDE+=" (subpath $(q "$1/envs"))"
  for r in "${CONDA_ROOTS[@]}"; do case $1 in "$r"/envs/*) CONDA_ENVS+=" (subpath $(q "$1"))" ;; esac; done; return 0
}
venv_base() {  # the installation a venv was made from, from pyvenv.cfg's home line; nothing (with a note) if it is gone
  local home; home=$(sed -n 's/^home[[:space:]]*=[[:space:]]*//p' "$1" | sed 's/[[:space:]]*$//' | tr -d '\r' | head -1)
  if [ -n "$home" ] && [ -d "$home" ]; then pyroot "$(cd "$home/.." && pwd -P)" "${2:-explicit}"; else echo "note: $1 points to a missing installation ($home)" >&2; fi
  return 0
}
add() { if risky "$2"; then echo "refusing a read grant that opens too much: $2" >&2; exit 2; fi; READ+=" ($1 $(q "$2"))"; }
for g in "$@"; do   # projects first, so file grants can be checked against them
  case $g in project:*)
    p=${g#project:}; [ -d "$p" ] || { echo "project not found: $p" >&2; exit 2; }
    rp=$(cd "$p" && pwd -P); top=$(git -C "$rp" -c core.fsmonitor=false rev-parse --show-toplevel 2>/dev/null || true)
    [ -n "$top" ] && [ "$(cd "$top" && pwd -P)" = "$rp" ] || { echo "project must be a Git repository's top folder: $rp" >&2; exit 2; }
    add subpath "$rp"; PROJECTS+=("$rp")
    while IFS= read -r -d '' cfg; do
      b=$(venv_base "$cfg" auto); if [ -n "$b" ] && [ -d "$b" ]; then if ! base_ok "$b"; then echo "skipping $cfg: its installation would open too much" >&2; else grant_base "$b"; fi; fi
    done < <(find "$rp" -maxdepth 8 \( -name .git -o -name node_modules \) -prune -o -name pyvenv.cfg -type f -print0 2>/dev/null) ;;
  esac
done
gitq() { git -C "$1" -c core.fsmonitor=false -c core.hooksPath=/dev/null "${@:2}"; }   # Git read as data: no repository programs run
PYI_GEN=/usr/bin/python3
in_project() { local pr; for pr in "${PROJECTS[@]:-}"; do [ -n "$pr" ] && case $1 in "$pr"/*) return 0 ;; esac; done; return 1; }
for g in "$@"; do
  kind=${g%%:*}; p=${g#*:}
  [ "$kind" != "$g" ] || { echo "grant needs a kind (project:, runtime:, file:, hide:): $g" >&2; exit 2; }
  case $kind in
    project) ;;
    runtime)
      [ -x "$p" ] && [ -f "$p" ] || { echo "runtime must be an interpreter file: $p" >&2; exit 2; }
      rp="$(cd "$(dirname "$p")" && pwd -P)/$(basename "$p")"; real=$(cd "$(dirname "$(readlink -f "$p")")" && pwd -P)
      if [ -f "$(dirname "$(dirname "$rp")")/pyvenv.cfg" ]; then   # a virtual environment: its folder and its base installation
        env=$(dirname "$(dirname "$rp")"); in_project "$env" || add subpath "$env"
        home=$(sed -n 's/^home[[:space:]]*=[[:space:]]*//p' "$env/pyvenv.cfg" | sed 's/[[:space:]]*$//' | tr -d '\r' | head -1)
        [ -d "$home" ] || { echo "runtime $p: its base installation is missing ($home)" >&2; exit 2; }
        b=$(venv_base "$env/pyvenv.cfg"); base=$(cd "$home/.." && pwd -P)
      else
        base=$(dirname "$real"); b=$(pyroot "$base")
      fi
      # an explicitly requested runtime is granted or refused, never silently left unreadable
      case $b in /private/tmp|/tmp|/Users|/Users/Shared|/Volumes|/Volumes/*/*) ;; /Volumes/*) echo "refusing a runtime whose installation is a whole volume: $b" >&2; exit 2 ;; esac
      case $b in /private/tmp|/tmp|/Users|/Users/Shared|/Volumes) echo "refusing a runtime whose installation is a top-level folder: $b" >&2; exit 2 ;; esac
      if [ -n "$b" ]; then base_ok "$b" || { echo "refusing a runtime whose installation would open too much: $b" >&2; exit 2; }; grant_base "$b"
      else case $base in "$H"/*) echo "runtime $p is not under a known Python installer: $base" >&2; exit 2 ;; esac; fi ;;
    file)
      [ -f "$p" ] || { echo "file not found: $p" >&2; exit 2; }
      rp="$(cd "$(dirname "$p")" && pwd -P)/$(basename "$p")"
      case $rp in "$H/Documents"/*) in_project "$rp" || { echo "a file under ~/Documents must belong to a granted project: $rp" >&2; exit 2; } ;; esac
      add literal "$rp" ;;
    hide)
      [ -e "$p" ] || { echo "hide target not found: $p" >&2; exit 2; }
      if [ -d "$p" ]; then hp=$(cd "$p" && pwd -P); HIDE+=" (subpath $(q "$hp"))"; else hp="$(cd "$(dirname "$p")" && pwd -P)/$(basename "$p")"; HIDE+=" (literal $(q "$hp"))"; fi
      # Git metadata could hold the hidden bytes (any branch, stash, reflog or loose object): a project with a hidden
      # path exposes none of its Git metadata: every .git inside it (nested repositories too), the resolved Git and
      # common directories (a relocated --separate-git-dir), the targets of .git files and alternate object stores.
      # If they cannot all be located, the grant is refused: supply a screened copy instead.
      for pr in "${PROJECTS[@]:-}"; do
        [ -n "$pr" ] || continue; case $hp in "$pr"/*) ;; *) continue ;; esac
        gds=$( { gitq "$pr" rev-parse --absolute-git-dir && gitq "$pr" rev-parse --path-format=absolute --git-common-dir; } 2>/dev/null ) \
          || { echo "cannot locate the Git metadata of $pr, so $hp cannot be hidden reliably: grant a screened copy instead" >&2; exit 2; }
        while IFS= read -r -d '' g; do
          if [ -d "$g" ]; then gds+=$'\n'"$g"
          else t=$(sed -n 's/^gitdir:[[:space:]]*//p' "$g" | head -1); gds+=$'\n'"$g"
               [ -n "$t" ] && { case $t in /*) ;; *) t="$(dirname "$g")/$t" ;; esac; [ -d "$t" ] && gds+=$'\n'"$(cd "$t" && pwd -P)"; }; fi
        done < <(find "$pr" -name .git -print0 -prune 2>/dev/null)
        while IFS= read -r g; do
          [ -n "$g" ] && [ -e "$g" ] || continue
          if [ -d "$g" ]; then HIDE+=" (subpath $(q "$g"))"; else HIDE+=" (literal $(q "$g"))"; fi
          if [ -d "$g/objects" ]; then   # alternate object stores, relative to the store that names them, followed through chains
            alts=$("$PYI_GEN" -I -X utf8 -c 'import os,sys
seen, todo, out = set(), [os.path.realpath(sys.argv[1])], []
while todo:
    o = todo.pop()
    if o in seen: continue
    seen.add(o); f = os.path.join(o, "info", "alternates")
    if not os.path.isfile(f): continue
    for line in open(f, errors="surrogateescape"):
        line = line.strip()
        if not line or line.startswith("#"): continue
        a = os.path.realpath(line if os.path.isabs(line) else os.path.join(o, line))
        if not os.path.isdir(a): print("UNRESOLVED " + a); continue
        out.append(a); todo.append(a)
print("\n".join(out))' "$g/objects") || { echo "cannot read the alternate object stores of $g: grant a screened copy instead" >&2; exit 2; }
            case $alts in *UNRESOLVED*) echo "an alternate object store of $g cannot be resolved: grant a screened copy instead" >&2; exit 2 ;; esac
            while IFS= read -r alt; do [ -n "$alt" ] && HIDE+=" (subpath $(q "$alt"))"; done <<< "$alts"
          fi
        done < <(printf '%s\n' "$gds" | sort -u)
        echo "note: $pr has a hidden path, so all its Git metadata is hidden as well" >&2
      done ;;
    *) echo "unknown grant kind: $kind" >&2; exit 2 ;;
  esac
done

# the CLI's program, and what it may read and write in its own state folder; the rest of that folder stays closed
SR=""; SW=""; LOCK=""
case $T in
  claude)
    # Claude's login comes from the keychain through /usr/bin/security, so its reviewer can read the keychain too (known gap)
    READ+=" (subpath $(q "$H/.local/share/claude")) (literal $(q "$H/.local/bin/claude")) (subpath $(q "$H/Library/Keychains"))" ;;
  codex)
    # the login is read-only: reviewers cannot change the login that ordinary sessions use
    # agents/ (custom agent definitions) read-only: Codex 0.169.1 stops at start-up when a present agents folder is unreadable
    for f in auth.json auth.json.lock auth.lock installation_id models_cache.json cache tmp log .sandbox_migration .sqlite-maintenance.lock agents; do SR+=" (subpath $(q "$ST/$f"))"; done
    for f in auth.json.lock auth.lock installation_id cache tmp log .sqlite-maintenance.lock; do SW+=" (subpath $(q "$ST/$f"))"; done
    DB=" (regex #\"^$(rx "$ST")/(logs|state|queue|goals)_[0-9]+\\.sqlite(-shm|-wal)?\$\")"; SR+="$DB"; SW+="$DB"
    # Codex rewrites models_cache.json at the top of its home through a temporary file and a rename
    SW+=" (literal $(q "$ST/models_cache.json")) (regex #\"^$(rx "$ST")/\\.tmp[^/]*\$\")"
    LOCK=" (literal $(q "$ST/auth.json")) (regex #\"^$(rx "$ST")/(config\\.toml|[^/]*\\.config\\.toml|managed_config\\.toml|requirements\\.toml|AGENTS(\\.override)?\\.md|hooks\\.json|\\.env|memories[^/]*|rules|skills|plugins|prompts|automations)(/|\$)\")" ;;
  agy)
    READ+=" (literal $(q "$H/.local/bin/agy")) (subpath $(q "$H/Library/Keychains"))"
    # its own folder and the few top-level files it needs; not the separate Gemini CLI login or global customizations
    SR=" (subpath $(q "$ST/antigravity-cli")) (literal $(q "$ST")) (subpath $(q "$ST/config/projects")) (literal $(q "$ST/config"))"
    for f in installation_id google_accounts.json settings.json state.json projects.json config/config.json; do SR+=" (literal $(q "$ST/$f"))"; done
    for f in brain conversations log cache implicit annotations crashes persistent_terminals; do SW+=" (subpath $(q "$ST/antigravity-cli/$f"))"; done
    for f in settings.json hooks.json mcp_config.json plugins skills rules knowledge; do HIDE+=" (subpath $(q "$ST/antigravity-cli/$f"))"; done
    HIDE+=" (literal $(q "$ST/oauth_creds.json")) (literal $(q "$ST/config/mcp_config.json"))" ;;
esac
# the CLI's real program file, wherever it is installed
[ -n "${AUDIT_CLI_BIN:-}" ] && [ -f "$AUDIT_CLI_BIN" ] && READ+=" (literal $(q "$(cd "$(dirname "$AUDIT_CLI_BIN")" && pwd -P)/$(basename "$AUDIT_CLI_BIN")"))"
# folders on the way to the reviewer's folder: listing their names lets the CLI find its working folder
d=$R; while [ "$d" != / ]; do d=$(dirname "$d"); READ+=" (literal $(q "$d"))"; done
TEC="(subpath $(q "$H/Library/Caches/TectonicProject.Tectonic"))"

cat <<P
(version 1)
(allow default)
; no launchd jobs, app launches, Apple Events, preferences, clipboard or mounts: each reaches outside the file rules
(deny job-creation)
(deny lsopen)
(deny appleevent-send)
(deny user-preference-read user-preference-write file-mount)
(deny mach-lookup (global-name "com.apple.pasteboard.1"))
; no signals to processes outside this reviewer's sandbox, no input event taps (WindowServer), no Spotlight index
(deny signal)
(allow signal (target same-sandbox))
(deny hid-control)
(deny iokit-open-user-client (iokit-user-client-class "IOHIDLibUserClient") (iokit-user-client-class "IOHIDParamUserClient") (iokit-user-client-class "IOHIDEventServiceFastPathUserClient"))
(deny mach-lookup (global-name "com.apple.windowserver.active") (global-name "com.apple.metadata.mds") (global-name "com.apple.metadata.mds.legacy"))
; no Shortcuts (a shortcut runs outside the sandbox: tested, listing and the run request both fail), no microphone or camera
(deny mach-lookup (global-name-regex #"^com\.apple\.(siriactionsd|shortcuts|siri|linkd|intelligenceflow|WorkflowKit|ToolKit)"))
(deny device-microphone device-camera)
; no connections to services on this Mac (public web stays open); DNS and the system log stay reachable
(deny network-outbound (remote ip "localhost:*"))
; IPv6 too: this Mac's addresses written as ::ffff:a.b.c.d slipped past the localhost rule (round 7); only this tcp6/udp6
; form closes them without opening anything else (tested; an "ip6" deny unexpectedly re-opened IPv4 to this Mac)
(deny network-outbound (remote tcp6 "*:*") (remote udp6 "*:*"))
(deny network-outbound (remote unix-socket))
(allow network-outbound (remote unix-socket (path-literal "/private/var/run/mDNSResponder")) (remote unix-socket (path-literal "/private/var/run/syslog")))
(deny network-bind network-inbound)
; reads: nothing under /Users, /tmp, the per-user temp and cache folders or /Volumes, except what is listed
(deny file-read-data (subpath "/Users") (subpath "/private/tmp") (subpath $(q "$UT")) (subpath $(q "$UC")) (subpath $(q "$UD/0")) (subpath "/Volumes"))
(allow file-read* (subpath $(q "$R/pack")) (subpath $(q "$R/tmp")) (literal $(q "$R")) $TEC$READ$SR)
(allow file-read-data (subpath $(q "$R/pack")) (subpath $(q "$R/tmp")) (literal $(q "$R")) $TEC$READ$SR)
; writes: only the reviewer's copy and temp folder, terminals and null devices, and the CLI's own runtime files
(deny file-write*)
(allow file-write* (subpath $(q "$R/pack")) (subpath $(q "$R/tmp")) (literal "/dev/null") (literal "/dev/zero") (literal "/dev/dtracehelper") (literal "/dev/ptmx") (literal "/dev/tty") (regex #"^/dev/fd/")$SW)
; other sessions' terminals: neither read nor written
(deny file-read-data file-write-data (regex #"^/dev/ttys[0-9]+\$"))
; the reviewer's own new terminals (opened through /dev/ptmx; the kernel tags each with a pty extension) stay usable, as in Apple's application.sb
; (tested: this data-only form works; the file-read*/file-write* form breaks openpty and forkpty)
(allow file-read-data file-write-data (require-all (regex #"^/dev/ttys[0-9]+\$") (extension "com.apple.sandbox.pty")))
; hard links and clones only inside the reviewer's copy and temp folder
(deny file-link file-clone)
(allow file-link file-clone (subpath $(q "$R/pack")) (subpath $(q "$R/tmp")))
P
# agy rewrites its two-line shell helper before running commands: content only (no links, renames, modes or flags);
# the launcher writes a clean copy before every run and checks it afterwards
[ "$T" = agy ] && printf '%s\n' "(allow file-write-data (literal $(q "$ST/antigravity-cli/bin/agentapi")))"
# agy runs its own helper server on a localhost port, so its reviewers keep localhost (known gap)
[ "$T" = agy ] && printf '%s\n' "; agy: its helper server needs localhost" "(allow network-bind network-inbound (local ip \"localhost:*\"))" "(allow network-outbound (remote ip \"localhost:*\"))"
[ -z "$LOCK" ] || printf '%s\n' "; never writable: files ordinary sessions trust or run" "(deny file-write*$LOCK)"
[ -z "$CONDA_HIDE" ] || printf '%s\n' "; a granted conda base keeps its other environments closed; a granted environment stays open" "(deny file-read* file-read-data$CONDA_HIDE)"
[ -z "$CONDA_HIDE$CONDA_ENVS" ] || [ -z "$CONDA_ENVS" ] || printf '%s\n' "(allow file-read* file-read-data$CONDA_ENVS)"
[ -z "$HIDE" ] || printf '%s\n' "; hidden even inside a granted project" "(deny file-read* file-read-data$HIDE)"
