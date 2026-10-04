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

# Secret-looking assignments (signing / service / private keys). Extra chars
# between the keyword and '=' are allowed, e.g. SIGNING_KEY_HEX=, as is a
# closing quote, so a JSON key ("service_role_secret": "eyJ…") is caught too.
pat='(SIGNING|SERVICE_ROLE|PRIVATE|SECRET|PRIV)[A-Za-z_]*["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"']?[0-9A-Za-z_/+-]{24,}'

# A value that is ALL-CAPS with underscores is an env var NAME, not a key: real
# keys are lowercase hex or mixed-case base64. Dropping those lets prose name
# the variable it expects ("Secret: ENTITLEMENT_SIGNING_KEY_HEX"). An
# underscore is required, so an upper-case hex seed still trips the guard.
allow='[=:][[:space:]]*["'"'"']?[A-Z][A-Z0-9]*(_[A-Z0-9]+)+([^0-9A-Za-z_/+-]|$)'

# Only ADDED lines are scanned. A '-' line removes content that is already in
# history, so flagging it blocks the very commit that takes the secret back
# out — a deleted comment naming ENTITLEMENT_SIGNING_KEY_HEX wedged a 151-file
# commit exactly this way.
scan() {
  git diff --cached -- "$@" 2>/dev/null \
    | grep -E '^\+' | grep -vE '^\+\+\+ ' \
    | grep -iE "$pat" \
    | grep -vE "$allow" \
    | head -1 || true
}

bad_content="$(scan)"

if [ -n "$bad_files" ] || [ -n "$bad_content" ]; then
  echo "🚫 BLOCKED: a secret appears to be staged." >&2
  [ -n "$bad_files" ] && echo "  files: $bad_files" >&2
  if [ -n "$bad_content" ]; then
    echo "  an added line looks like a key assignment, in:" >&2
    # Name the files so the match can be found without re-running the regex by
    # hand; the value itself is deliberately not echoed.
    while IFS= read -r f; do
      if [ -n "$(scan "$f")" ]; then echo "    $f" >&2; fi
    done < <(git diff --cached --name-only 2>/dev/null)
  fi
  echo "  Unstage it (git restore --staged <file>) before committing." >&2
  exit 2
fi
exit 0
