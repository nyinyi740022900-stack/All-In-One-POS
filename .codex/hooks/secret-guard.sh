#!/usr/bin/env bash
# PreToolUse(Bash) guard: block `git commit`/`git push` if a secret is staged.
# Reads the tool-call JSON on stdin; exit 2 blocks the call and shows stderr.
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || true)"

case "$cmd" in
  *"git commit"*|*"git push"*) ;;
  *) exit 0 ;;  # not a commit/push — nothing to check
esac

# Secret-looking file names staged?
bad_files="$(git diff --cached --name-only 2>/dev/null \
  | grep -iE 'env\.local\.json|\.pem$|id_rsa|service[_-]?role' || true)"

# Secret-looking assignments in the staged diff (signing / service / private
# keys). Allows extra chars between the keyword and '=' (e.g. SIGNING_KEY_HEX=).
bad_content="$(git diff --cached 2>/dev/null \
  | grep -iE '(SIGNING|SERVICE_ROLE|PRIVATE|SECRET|PRIV)[A-Za-z_]*[[:space:]]*[=:][[:space:]]*["'"'"']?[0-9A-Za-z_/+-]{24,}' \
  | head -1 || true)"

if [ -n "$bad_files" ] || [ -n "$bad_content" ]; then
  echo "🚫 BLOCKED: a secret appears to be staged." >&2
  [ -n "$bad_files" ] && echo "  files: $bad_files" >&2
  [ -n "$bad_content" ] && echo "  content matched a key assignment" >&2
  echo "  Unstage it (git restore --staged <file>) before committing." >&2
  exit 2
fi
exit 0
