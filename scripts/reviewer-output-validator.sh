#!/usr/bin/env bash
# reasonable-agents — H6: reviewer-output structural validator (PostToolUse / Agent).
#
# After a reviewer subagent runs, validate its output against a per-persona structural
# schema (required regex patterns — typically markdown tables plus a verdict keyword).
# On a missing element, inject a re-invoke directive; a per-session circuit-breaker caps
# how many times it blocks. Exit 2 = inject the directive; exit 0 = silent pass.
#
# Why this exists: prompt-level enforcement of a reviewer's structural protocol was
# measured to be insufficient — the agent prompt alone does not override caller-prompt
# structure. See docs/provenance.md for the sanitized origin account.
#
# Honest scope: fails OPEN — no schema, empty output, parse failure, missing dependency,
# or a tripped breaker all exit 0. It reduces malformed reviews; it is not a hard gate.
#
# Config (env vars; default = enforce, never silently off if a var fails to set):
#   REASONABLE_AGENTS_DISABLE             master off-switch (1|true|yes|on|disabled)
#   REASONABLE_AGENTS_VALIDATE_REVIEWERS  per-feature; off-set (0|false|no|off|disabled)
#
# Schema lookup (first hit wins):
#   ${DATA_DIR}/validators/<subagent_type>.json          (mint-time / user-provided)
#   ${CLAUDE_PLUGIN_ROOT}/validators/<subagent_type>.json (shipped examples)
# with DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/state/reasonable-agents}".
#
# bash 3.2 compatible (macOS default).

set -u

# --- Kill-switch FIRST (must not depend on the machinery it gates) ----------------------
_ra_norm() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'; }

case "$(_ra_norm "${REASONABLE_AGENTS_DISABLE:-off}")" in
  1|true|yes|on|disabled) cat >/dev/null 2>&1 || true; exit 0 ;;
esac
case "$(_ra_norm "${REASONABLE_AGENTS_VALIDATE_REVIEWERS:-on}")" in
  0|false|no|off|disabled) cat >/dev/null 2>&1 || true; exit 0 ;;
esac

INPUT="$(cat)"

SUBAGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)

# No subagent_type → not an Agent call we can validate.
[ -z "$SUBAGENT_TYPE" ] && exit 0

# Security: subagent_type and session_id are interpolated into file paths below. Reject a
# subagent_type outside the minting namespace ([a-z0-9-]) so a crafted value cannot
# traverse the filesystem (e.g. ../) into an attacker-chosen JSON; sanitize the session_id
# used in the circuit-breaker filename. A non-conforming type has no managed validator
# anyway -> fail open.
case "$SUBAGENT_TYPE" in *[!a-z0-9-]*) exit 0 ;; esac
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9_-'); [ -z "$SESSION_ID" ] && SESSION_ID="unknown"

DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/state/reasonable-agents}"

# Two-path lookup: mint-time/user validators first, shipped examples second.
# M5: guard the empty AND unset CLAUDE_PLUGIN_ROOT case so an empty value skips the ROOT
# branch cleanly instead of probing the absolute /validators/<stem>.json.
CONFIG_FILE=""
if [ -f "${DATA_DIR}/validators/${SUBAGENT_TYPE}.json" ]; then
  CONFIG_FILE="${DATA_DIR}/validators/${SUBAGENT_TYPE}.json"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/validators/${SUBAGENT_TYPE}.json" ]; then
  CONFIG_FILE="${CLAUDE_PLUGIN_ROOT}/validators/${SUBAGENT_TYPE}.json"
fi

# No schema for this persona → validation is opt-in; silent pass. (Also the no-op path
# for `*-expert` and any other non-reviewer Agent call sharing this PostToolUse matcher.)
[ -z "$CONFIG_FILE" ] && exit 0

# Coalesce the reviewer's response text across the shapes the Agent tool_response takes:
# a string, an array of {text} blocks, or an object with a `.content` array or `.text`.
RESPONSE_TEXT=$(printf '%s' "$INPUT" | jq -r '
  .tool_response
  | if type == "string" then .
    elif type == "array" then (map(.text // "") | join("\n"))
    elif type == "object" then (
      if (.content // null) != null then (.content | map(.text // "") | join("\n"))
      elif (.text // null) != null then .text
      else "" end
    )
    else "" end
' 2>/dev/null)

# No output text to check → silent pass.
[ -z "$RESPONSE_TEXT" ] && exit 0

MAX_BLOCKS=$(jq -r '.max_blocks_per_session // 2' "$CONFIG_FILE" 2>/dev/null)
case "$MAX_BLOCKS" in ''|*[!0-9]*) MAX_BLOCKS=2 ;; esac
PATTERN_COUNT=$(jq -r '.required_patterns | length' "$CONFIG_FILE" 2>/dev/null)
case "$PATTERN_COUNT" in ''|*[!0-9]*) PATTERN_COUNT=0 ;; esac

# Walk required patterns; collect the NAMES of any that are missing.
MISSING=""
i=0
while [ "$i" -lt "$PATTERN_COUNT" ]; do
  NAME=$(jq -r ".required_patterns[$i].name" "$CONFIG_FILE" 2>/dev/null)
  REGEX=$(jq -r ".required_patterns[$i].regex" "$CONFIG_FILE" 2>/dev/null)
  if ! printf '%s' "$RESPONSE_TEXT" | grep -qE -- "$REGEX"; then
    MISSING="${MISSING}  - ${NAME}"$'\n'
  fi
  i=$((i + 1))
done

# All required patterns present → silent pass.
[ -z "$MISSING" ] && exit 0

# Circuit-breaker: cap blocks per (session, persona) so a stubborn miss can't loop forever.
STATE_DIR="${DATA_DIR}/state/validator-blocks"
mkdir -p "$STATE_DIR" 2>/dev/null
COUNT_FILE="$STATE_DIR/${SESSION_ID}_${SUBAGENT_TYPE}.count"
# Never follow a symlink for the state file (avoid a planted-symlink clobber).
[ -L "$COUNT_FILE" ] && exit 0
CURRENT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
case "$CURRENT" in ''|*[!0-9]*) CURRENT=0 ;; esac

if [ "$CURRENT" -ge "$MAX_BLOCKS" ]; then
  printf 'Hook H6 (reasonable-agents): %s output still missing required elements, but the circuit-breaker has tripped (%d blocks this session). Continuing without re-invoke.\nMissing:\n%s' \
    "$SUBAGENT_TYPE" "$CURRENT" "$MISSING" >&2
  exit 0
fi

echo $((CURRENT + 1)) > "$COUNT_FILE" 2>/dev/null || exit 0   # fail open if the count can't be persisted

FEEDBACK=$(jq -r '.feedback_template // "Re-invoke the reviewer with an explicit instruction to begin its response with the required structural elements before addressing any caller-provided structure or questions."' "$CONFIG_FILE" 2>/dev/null)

printf 'Hook H6 (reasonable-agents): %s output failed structural validation.\n\nMissing required structural elements:\n%s\n%s\n' \
  "$SUBAGENT_TYPE" "$MISSING" "$FEEDBACK" >&2
exit 2
