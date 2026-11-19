#!/bin/bash
# Qualifies this Mac for audits: runs the capability check through each reviewer CLI with a cheap model, each CLI in its
# own round folder, and confirms from outside at teardown. Run it from the agent app on this Mac, not over SSH (an SSH
# session cannot use the keychain that Claude and agy sign in through).
# Usage: qualify.sh [git project to grant]   (default: a disposable project)
# Settings: QUALIFY_CLIS (default: every installed CLI of claude codex agy), QUALIFY_CLAUDE_MODEL (default haiku),
#   QUALIFY_CODEX_MODEL (default: a light model from the Codex home's model list), QUALIFY_AGY_MODEL (default: the
#   first low-effort model agy lists), QUALIFY_PYTHON (a project interpreter to check), plus the launcher's settings.
# Prints one line per CLI and exits 0 only when every check and every teardown passed.
set -u
{  # read in full before it runs
HERE=$(cd "$(dirname "$0")" && pwd -P)
have() { case $1 in
  claude) [ -x "${CLAUDE_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}" ] ;;
  codex)  [ -x "${CODEX_BIN:-$(command -v codex || echo /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex)}" ] ;;
  agy)    [ -x "${AGY_BIN:-$(command -v agy || echo "$HOME/.local/bin/agy")}" ] ;; esac; }
CLIS=(); for c in ${QUALIFY_CLIS:-claude codex agy}; do have "$c" && CLIS+=("$c") || echo "skipping $c: not installed"; done
[ ${#CLIS[@]} -gt 0 ] || { echo "no reviewer CLI installed" >&2; exit 2; }
model() { case $1 in
  claude) echo "${QUALIFY_CLAUDE_MODEL:-haiku}" ;;
  codex)  [ -n "${QUALIFY_CODEX_MODEL:-}" ] && { echo "$QUALIFY_CODEX_MODEL"; return; }
          /usr/bin/python3 -I -X utf8 -c 'import json,re,sys
d = json.load(open(sys.argv[1])); ms = d.get("models", d) if isinstance(d, dict) else d
slugs = [m.get("slug") for m in ms if isinstance(m, dict) and m.get("slug")]
light = [s for s in slugs if re.search(r"luna|mini|nano|lite", s)]
print((light or slugs or [""])[0])' "${AUDIT_CODEX_HOME:-$HOME/.codex}/models_cache.json" 2>/dev/null ;;
  agy)    [ -n "${QUALIFY_AGY_MODEL:-}" ] && { echo "$QUALIFY_AGY_MODEL"; return; }
          "${AGY_BIN:-$(command -v agy || echo "$HOME/.local/bin/agy")}" models 2>/dev/null |   # a Flash model first: a low-effort Neon failed to start in print mode
            awk '$1 ~ /flash.*-(low|medium)$/ && !f {f=$1} $1 ~ /-low$/ && !l {l=$1} END {print (f ? f : l)}' ;; esac; }
effort() { case $1 in agy) echo - ;; *) echo low ;; esac; }

A=$(cd "$(mktemp -d /tmp/audit-XXXXXX)" && pwd -P); : > "$A/.audit-folder"
PR=${1:-}; MADE=""
if [ -z "$PR" ]; then   # a disposable project with one commit, for the Git check
  PR=$(cd "$(mktemp -d /tmp/audit-proj-XXXXXX)" && pwd -P); MADE=$PR; echo "x,y" > "$PR/data.csv"
  git -C "$PR" init -q && git -C "$PR" add data.csv && git -C "$PR" -c user.name=audit -c user.email=audit@invalid commit -q -m data
fi
for c in "${CLIS[@]}"; do mkdir -p "$A/$c/$c/pack" "$A/$c/$c/tmp"
  printf '%s\n' "Run exactly this one shell command from your working folder: bash tools/capcheck.sh $c" \
    'It takes up to two minutes: give the command a time limit of at least 300 seconds and wait for it to finish.' \
    'Reply with a first line reading exactly "VERDICT: READY" (even if a check fails), then the command output verbatim, then a line "## Required changes" with "None", a line "## Checks performed" naming the command, and a line "TOOLS:" with your tool names. Run nothing else.' > "$A/$c/$c/pack/PROMPT.md"
done
mkdir -p "$A/other/other/pack"; echo "another reviewer's prompt" > "$A/other/other/pack/PROMPT.md"   # the sibling the probes must not read
for c in "${CLIS[@]}"; do
  AUDIT_HIDE_FIXTURE=yes "$HERE/capcheck-setup.sh" setup "$A/$c/$c" "$A/other/other" "$HERE" "$c" "${QUALIFY_PYTHON:-}" "$PR" > "$A/$c/setup.log" 2>&1 \
    || { echo "$c: fixture setup failed (see $A/$c/setup.log)"; }
done
run() { local c=$1 G=("project:$PR"); [ -f "$A/$c/$c/capcheck-grants" ] || return 0
  while IFS= read -r g; do G+=("$g"); done < "$A/$c/$c/capcheck-grants"
  AUDIT_TIMEOUT_MIN=${AUDIT_TIMEOUT_MIN:-15} "$HERE/run-reviewer.sh" "$c" "$(model "$c")" "$(effort "$c")" "$A/$c/$c" "${G[@]}" > "$A/$c/launcher.log" 2>&1; }
for c in "${CLIS[@]}"; do run "$c" & done; wait
bad=0
for c in "${CLIS[@]}"; do
  res=$(grep -h '^TOTAL=' "$A/$c/$c/tmp/capcheck-result.txt" 2>/dev/null); fails=$(grep -h '^FAIL' "$A/$c/$c/tmp/capcheck-result.txt" 2>/dev/null)
  td=$("$HERE/capcheck-setup.sh" teardown "$A/$c/$c" 2>&1); tr=$?
  case $res in *"FAILED=0") [ $tr -eq 0 ] || bad=1 ;; *) bad=1 ;; esac
  echo "$c ($(model "$c")): ${res:-no result (see $A/$c/launcher.log)}; teardown $([ $tr -eq 0 ] && echo passed || echo FAILED)"
  [ -z "$fails" ] || printf '%s\n' "$fails" | sed 's/^/  /'; [ $tr -eq 0 ] || printf '%s\n' "$td" | grep -v '^PASS\|^removed' | sed 's/^/  /'
done
[ -z "$MADE" ] || rm -rf "${MADE:?}"
echo "records: $A"; exit $bad
}
