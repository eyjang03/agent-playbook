#!/bin/bash
# Capability check, run by a reviewer from inside its sandbox: bash capcheck.sh <name>
# Reads capcheck.conf (written by capcheck-setup.sh outside the sandbox, which also confirms every fixture exists).
# A "blocked" check passes only on a permission error, so a missing fixture or a broken command fails.
# Prints PASS/FAIL/INFO per line and "TOTAL=<n> FAILED=<m>"; exits 1 on any failure or an unexpected number of checks.
set -u
# the full output also goes to the reviewer's temp folder, so the orchestrator reads the real result even when a model
# copies it only in part (it happened with a cheap qualification model)
if [ -z "${CAPCHECK_TEE:-}" ]; then CAPCHECK_TEE=1 bash "$0" "$@" 2>&1 | tee "${TMPDIR:-.}/capcheck-result.txt"; exit "${PIPESTATUS[0]}"; fi
cd "$(dirname "$0")" || exit 1
N=${1:?usage: capcheck.sh <name>}
[ -f capcheck.conf ] || { echo "FAIL  capcheck.conf missing"; echo "TOTAL=0 FAILED=1"; exit 1; }
. ./capcheck.conf
for v in KBD_CONTROL TTY_PATH ENV_MARKER SLEEPER_PID SOCKET_PATH TAP_CONTROL SHARED_CANARY LISTEN_PORT LOCALHOST_EXPECT PREF_DOMAIN SIBLING ROOT STATE_PROBE_DIR CONFIG_FILE HOOK_FILE PRIVATE_FILE CANARY KEYCHAIN_SERVICE KEYCHAIN_EXPECT PROBE EXPECTED_CHECKS; do
  [ -n "${!v:-}" ] || { echo "FAIL  capcheck.conf lacks $v"; echo "TOTAL=0 FAILED=1"; exit 1; }
done
total=0; fails=0
# every tool a probe relies on must exist, so a missing tool can never pass as "blocked"
missing=""
for c in python3 curl git nc defaults pbpaste mdfind launchctl security osascript open ln cp ls cat ; do
  command -v "$c" >/dev/null 2>&1 || missing+=" $c"
done
[ -z "$missing" ] || { echo "FAIL  probes unavailable:$missing"; echo "TOTAL=0 FAILED=1"; exit 1; }
PERM='[Oo]peration not permitted|[Pp]ermission denied|error -54|\(-54\)'
ok() {
  local label=$1 out rc; shift; total=$((total+1)); out=$("$@" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then echo "PASS  $label"; else echo "FAIL  $label: exit $rc: ${out:0:150}"; fails=$((fails+1)); fi
}
blocked() {  # output of an allowed probe is not printed (it could be private)
  local label=$1 out rc; shift; total=$((total+1)); out=$("$@" 2>&1); rc=$?
  if [ $rc -eq 127 ] || printf '%s' "$out" | grep -q "command not found"; then echo "FAIL  $label: probe unavailable"; fails=$((fails+1))
  elif [ $rc -eq 3 ]; then echo "FAIL  $label: ${out:0:150}"; fails=$((fails+1))   # a wrapper's own verdict: the probe is broken
  elif [ $rc -ne 0 ] && printf '%s' "$out" | grep -Eq "$PERM"; then echo "PASS  $label (blocked)"
  elif [ $rc -eq 0 ]; then echo "FAIL  $label: allowed"; fails=$((fails+1))
  else echo "FAIL  $label: failed without a permission error, so the probe proves nothing: ${out:0:150}"; fails=$((fails+1)); fi
}
w() { echo x > "$1"; }                 # create a file
a() { printf '' >> "$1"; }              # open an existing or new file for writing without changing its content
# setup proved each of these works outside the sandbox, so a failure inside is the sandbox
# each wrapper reports a denial only on the message the sandbox actually produces (recorded on macOS 27);
# any other failure is "probe broken", which never counts as blocked
broken() { echo "probe broken: $*"; return 3; }   # exit 3 never counts as blocked, whatever the text says
pref_read()  { local o rc; o=$(defaults read "$1" key 2>&1); rc=$?; [ $rc -eq 0 ] && return 0
               case $o in *"Domain '$1' not found"*) echo "Operation not permitted: preference unreadable"; return 1 ;; esac; broken "exit $rc: ${o:0:100}"; }
pref_write() { local o rc; o=$(defaults write "$1" key2 x 2>&1); rc=$?; [ $rc -eq 0 ] && return 0
               case $o in *"Could not write domain $1"*) echo "Operation not permitted: preference unwritable"; return 1 ;; esac; broken "exit $rc: ${o:0:100}"; }
clip()       { local o rc; o=$(pbpaste 2>&1 >/dev/null); rc=$?; [ $rc -eq 0 ] && return 0   # the clipboard itself is never printed
               [ $rc -eq 1 ] && [ -z "$o" ] && { echo "Operation not permitted: clipboard unavailable"; return 1; }; broken "exit $rc: ${o:0:100}"; }
sig()  { kill -0 "$1"; }
# Apple Events: Finder runs whenever the user is logged in (setup confirmed it without sending an event); a real event
# to it is refused inside the sandbox as -600 (the app cannot be seen), -1743 (not authorized) or -54
aevent() { local o; o=$(osascript -e 'tell application "Finder" to count windows' 2>&1); [[ $o =~ ^[0-9]+$ ]] && return 0
           case $o in *"(-600)"*|*"(-1743)"*|*"(-54)"*) echo "Operation not permitted: Apple Event refused (${o##*: })"; return 1 ;; esac; broken "${o:0:100}"; }
shortcuts_list() { local o rc; o=$(shortcuts list 2>&1 >/dev/null); rc=$?; [ $rc -eq 0 ] && return 0   # names are never printed
                   case $o in *"communicate with a helper application"*) echo "Operation not permitted: Shortcuts unavailable"; return 1 ;; esac; broken "exit $rc: ${o:0:100}"; }
spot() { local n rc; n=$(mdfind -count -onlyin "$HOME/Documents" 'kMDItemContentTypeTree == "public.item"' 2>&1); rc=$?
         [ $rc -eq 0 ] && [[ $n =~ ^[0-9]+$ ]] && [ "$n" -gt 0 ] && return 0
         [ $rc -eq 0 ] && { [ -z "$n" ] || [ "$n" = 0 ]; } && { echo "Operation not permitted: Spotlight returned nothing"; return 1; }; broken "exit $rc: ${n:0:100}"; }
tap()  { local r; r=$(python3 -I -c 'import ctypes,ctypes.util
cg=ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreGraphics")); cf=ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreFoundation"))
cb=ctypes.CFUNCTYPE(ctypes.c_void_p,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_void_p)(lambda *a: a[2])
cg.CGEventTapCreate.restype=ctypes.c_void_p; t=cg.CGEventTapCreate(0,0,1,1<<10,cb,None)
print("created" if t else "refused"); t and cf.CFRelease(ctypes.c_void_p(t))' 2>&1 | tail -1)
         [ "$r" = created ] && return 0; [ "$r" = refused ] && { echo "Operation not permitted: event tap refused"; return 1; }; broken "${r:0:100}"; }
usock() { python3 -I -c 'import socket,sys
s=socket.socket(socket.AF_UNIX)
try: s.connect(sys.argv[1])
except PermissionError: print("Operation not permitted"); sys.exit(1)
except OSError as e: print(e); sys.exit(1)' "$1"; }
kbd()  { local r; r=$(python3 -I -c 'import ctypes,ctypes.util
k=ctypes.cdll.LoadLibrary(ctypes.util.find_library("IOKit"))
k.IOHIDManagerCreate.restype=ctypes.c_void_p; k.IOHIDManagerCreate.argtypes=[ctypes.c_void_p,ctypes.c_uint32]
k.IOHIDManagerSetDeviceMatching.argtypes=[ctypes.c_void_p,ctypes.c_void_p]
k.IOHIDManagerOpen.argtypes=k.IOHIDManagerClose.argtypes=[ctypes.c_void_p,ctypes.c_uint32]; k.IOHIDManagerOpen.restype=ctypes.c_int
m=k.IOHIDManagerCreate(None,0); k.IOHIDManagerSetDeviceMatching(m,None); r=k.IOHIDManagerOpen(m,0); k.IOHIDManagerClose(m,0)
print("opened" if r==0 else "refused %x" % (r & 0xffffffff))' 2>&1 | tail -1)
         [ "$r" = opened ] && return 0; [ "$r" = "refused e00002e2" ] && { echo "Operation not permitted: keyboards refused (kIOReturnNotPermitted)"; return 1; }; broken "${r:0:100}"; }
ownpty() { python3 -I -c 'import os,pty,signal
signal.alarm(20); pid,fd=pty.fork()
if pid==0: os.execv("/bin/echo",["echo","on-a-terminal"])
out=b""
while True:
  try: d=os.read(fd,100)
  except OSError: break
  if not d: break
  out+=d
os.waitpid(pid,0); assert b"on-a-terminal" in out, out'; }
term() { python3 -I -c 'import os,sys; os.close(os.open(sys.argv[1], os.O_RDONLY|os.O_NONBLOCK|os.O_NOCTTY))' "$1"; }
envread() { python3 -I -c 'import ctypes,sys
libc=ctypes.CDLL("/usr/lib/libSystem.B.dylib"); mib=(ctypes.c_int*3)(1,49,int(sys.argv[1])); n=ctypes.c_size_t(262144); b=ctypes.create_string_buffer(262144)
sys.exit(0 if libc.sysctl(mib,3,b,ctypes.byref(n),None,0)==0 and sys.argv[2].encode() in b.raw[:n.value] else 1)' "$1" "$2"; }
lh() { python3 -I -c 'import socket,sys
h, port = sys.argv[1], int(sys.argv[2])
if h == "mapped":   # the own LAN address as ::ffff:a.b.c.d, found here so it is never written into the pack
    try:
        u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.connect(("192.0.2.1", 9)); h = "::ffff:" + u.getsockname()[0]
    except OSError as e: print("probe broken: own address not found:", e); sys.exit(3)
s = socket.socket(socket.AF_INET6 if ":" in h else socket.AF_INET); s.settimeout(3)
try: s.connect((h, port))
except PermissionError: print("Operation not permitted"); sys.exit(1)
except OSError as e: print("probe broken: no connection:", e); sys.exit(3)' "$1" "$2"; }

ok      "python3 runs"                              python3 -c 'print(42)'
[ -n "${PROJECT_PYTHON:-}" ] && ok "project Python imports numpy" "$PROJECT_PYTHON" -c 'import numpy'
ok      "write in own copy"                         w "probe-$N.txt"
ok      "run a command on its own new terminal"     ownpty
ok      "zsh here-document"                         /bin/zsh -c $'cat >/dev/null <<EOF\nx\nEOF'
if [ "${TECTONIC:-no}" = yes ]; then ok "LaTeX builds a fresh PDF" sh -c 'rm -f t.pdf && tectonic t.tex >/dev/null 2>&1 && test -s t.pdf'
else echo "INFO  LaTeX probe skipped: Tectonic is not installed on this Mac"; fi
ok      "HTTPS"                                     curl -sf -o /dev/null --max-time 15 https://example.com
blocked "read another reviewer's copy"              cat "$SIBLING/PROMPT.md"
blocked "write another reviewer's copy"             w "$SIBLING/$PROBE"
blocked "write the launcher's folder"               w "$ROOT/$PROBE"
blocked "write under ~/Documents"                   w "$HOME/Documents/$PROBE"
blocked "write in home"                             w "$HOME/.$PROBE"
if [ -n "${BREW_DIR:-}" ]; then blocked "write in the Homebrew prefix ($BREW_DIR)" w "$BREW_DIR/$PROBE"
else echo "INFO  Homebrew-prefix probe skipped: no writable Homebrew prefix on this Mac"; fi
blocked "create a file in the CLI's state folder"   w "$STATE_PROBE_DIR/$PROBE"
blocked "change the CLI's settings"                 a "$CONFIG_FILE"
blocked "change a hook or instruction file"         a "$HOOK_FILE"
blocked "read a private CLI file"                   cat "$PRIVATE_FILE"
blocked "read a file in home"                       cat "$CANARY"
blocked "read a file in /Users/Shared"              cat "$SHARED_CANARY"
blocked "list ~/Documents"                          ls "$HOME/Documents"
blocked "list the per-user temp folder"             ls "$(getconf DARWIN_USER_TEMP_DIR)"
blocked "hard-link a private file into own copy"    ln "$CANARY" "link-$N"
blocked "clone a private file into own copy"        cp -c "$CANARY" "clone-$N"
blocked "read a preference"                         pref_read "$PREF_DOMAIN"
blocked "write a preference"                        pref_write "$PREF_DOMAIN"
blocked "read the clipboard"                        clip
# launchd cannot be queried from inside the sandbox: teardown checks from outside that no job exists
launchctl submit -l "$PROBE" -- /usr/bin/true >/dev/null 2>&1; echo "INFO  background job submitted; teardown decides"
if [ "$LOCALHOST_EXPECT" = blocked ]; then blocked "connect to a service on this Mac" lh 127.0.0.1 "$LISTEN_PORT"
  [ "${MAPPED_CONTROL:-no}" = yes ] && blocked "connect to this Mac through its IPv6-mapped address" lh mapped "$LISTEN_PORT"
elif lh 127.0.0.1 "$LISTEN_PORT" >/dev/null; then echo "INFO  localhost reachable (known gap: this CLI needs localhost)"; else echo "INFO  localhost not reachable"; fi
blocked "open an app"                               open -g -a Calculator
blocked "signal a process outside the sandbox"     sig "$SLEEPER_PID"
blocked "list files through Spotlight"              spot
[ "${SHORTCUTS_CONTROL:-no}" = yes ] && blocked "reach Shortcuts (a shortcut runs outside the sandbox)" shortcuts_list
if [ "$TAP_CONTROL" = yes ]; then blocked "create a keyboard event tap"  tap
else echo "INFO  event-tap probe skipped: the orchestrator app has no input-monitoring permission"; fi
blocked "connect to another app's local socket"     usock "$SOCKET_PATH"
if [ "$KBD_CONTROL" = yes ]; then blocked "open the keyboards (input monitoring)" kbd
else echo "INFO  keyboard probe skipped: the orchestrator app has no input-monitoring permission"; fi
[ "$TTY_PATH" != none ] && blocked "open another session's terminal"  term "$TTY_PATH"
if envread "$SLEEPER_PID" "$ENV_MARKER"; then echo "INFO  other processes' environments readable (known gap: the sandbox cannot close this; a separate macOS user would)"
else echo "INFO  other processes' environments not readable"; fi
[ -n "${GIT_PROJECT:-}" ] && ok "git log in the granted project" git -C "$GIT_PROJECT" log -1 --format=%h
if [ -n "${HIDDEN_FILE:-}" ]; then   # a hide: grant: the path and its project's Git metadata are both unreadable
  blocked "read a hidden file in a granted project"   cat "$HIDDEN_FILE"
  blocked "read the Git history of that project"      cat "$HIDDEN_PROJECT/.git/HEAD"
fi
if [ "${FINDER_CONTROL:-no}" = yes ]; then blocked "send an Apple Event" aevent
else echo "INFO  Apple Event probe skipped: Finder is not running"; fi
# keychain: setup proved the dummy item's secret can be read outside the sandbox; the secret is never printed
total=$((total+1))
kco=$(security find-generic-password -s "$KEYCHAIN_SERVICE" 2>&1 >/dev/null); kcr=$?
if [ $kcr -eq 0 ]; then
  if security find-generic-password -s "$KEYCHAIN_SERVICE" -w >/dev/null 2>&1; then kc="secret readable"; else kc="item found, secret not readable"; fi
elif [ $kcr -eq 44 ] && printf '%s' "$kco" | grep -q "could not be found in the keychain"; then kc="item not found"
else kc="probe broken: exit $kcr: ${kco:0:100}"; fi
if [ "$KEYCHAIN_EXPECT" = blocked ]; then
  if [ "$kc" = "item not found" ]; then echo "PASS  read the dummy keychain item (blocked)"; else echo "FAIL  read the dummy keychain item: $kc"; fails=$((fails+1)); fi
else
  case $kc in "probe broken"*) echo "FAIL  dummy keychain item: $kc"; fails=$((fails+1)) ;;
    *) echo "INFO  dummy keychain item: $kc (known gap: this CLI signs in through the keychain)" ;; esac
  IFS=',' read -ra KS <<< "${KNOWN_SERVICES:-}"
  for s in "${KS[@]}"; do   # real items: existence only, their secrets are not read
    if security find-generic-password -s "$s" >/dev/null 2>&1; then echo "INFO    also found (secret not tested): $s"; fi
  done
fi
[ "$total" -eq "$EXPECTED_CHECKS" ] || { echo "FAIL  ran $total checks, expected $EXPECTED_CHECKS"; fails=$((fails+1)); }
echo "TOTAL=$total FAILED=$fails"; [ $fails -eq 0 ]
