#!/usr/bin/env bash
# reasonable-agents — H6: reviewer-output structural validator (PostToolUse / Agent).
#
# After a reviewer subagent runs, validate its output against a per-persona structural
# schema (required regex patterns — typically markdown tables plus a verdict keyword).
# On a missing element, inject a re-invoke directive; a per-session circuit-breaker caps
# how many times it blocks. Exit 2 = inject the directive; exit 0 = pass (silent, or a
# non-blocking note on stdout as hookSpecificOutput.additionalContext).
#
# Why this exists: prompt-level enforcement of a reviewer's structural protocol was
# measured to be insufficient — the agent prompt alone does not override caller-prompt
# structure. See docs/provenance.md for the sanitized origin account.
#
# Where the report lives — the Agent tool_response takes five shapes:
#   1. Inline: report in .content[].text (older callers: a bare string or {text} array).
#   2. Hand-back (CLI 2.1.28x+): the subagent called SubagentHandback, so .content holds
#      only a short pointer ("This agent's report was delivered to you as a message
#      from ...") and the report rides in .handbackReport.text.
#   3. Pointer-only: a hand-back pointer with no .handbackReport. The report is read from
#      the subagent's own transcript (its last SubagentHandback message). If that is
#      unreachable too, H6 cannot see the report, so it emits a non-blocking note rather
#      than blocking on the pointer text.
#   4. Withheld (.handback == "withheld"): the harness delivered no report. Non-blocking
#      note; a re-invoke directive would loop on a report that is never delivered.
#   5. async_launched (background Agent call): no report yet; silent pass.
# Precedence: withheld → note; else .handbackReport.text → subagent transcript → note.
#
# Honest scope: fails OPEN — no schema, empty inline output, parse failure, missing
# dependency, an unreachable or withheld hand-back report, or a tripped breaker all exit 0
# (silent, or a non-blocking note). One deliberate exception: a hand-back that delivered an
# EMPTY report is a deficient review, so it is validated and blocks (breaker-capped). It
# reduces malformed reviews; it is not a hard gate.
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

# Non-blocking note Claude can see. Under PostToolUse, stderr at exit 0 reaches no one and
# exit 1 reaches only the user; stdout additionalContext is the channel. jq keeps it valid
# JSON whatever the message holds.
note() {
  jq -cn --arg ctx "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
}

# Last SubagentHandback message from the subagent's transcript, which sits beside the
# parent transcript: <transcript minus .jsonl>/subagents/agent-<agentId>.jsonl. Prints the
# message prefixed with "x" (so an empty report is distinguishable from none); prints
# nothing when unreachable. Read-only. agentId is interpolated into the path, so anything
# outside [a-z0-9] is rejected (not stripped), the transcript path must be absolute, and a
# symlinked transcript file is refused.
subagent_handback() {
  local tpath agent_id file
  tpath=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  agent_id=$(printf '%s' "$INPUT" | jq -r '(.tool_response | objects | .agentId | strings) // empty' 2>/dev/null)
  case "$agent_id" in ''|*[!a-z0-9]*) return 0 ;; esac
  case "$tpath" in /*.jsonl) ;; *) return 0 ;; esac
  file="${tpath%.jsonl}/subagents/agent-${agent_id}.jsonl"
  { [ -f "$file" ] && [ ! -L "$file" ]; } || return 0
  # The LAST hand-back message, not the last assistant message: after handing back, the
  # subagent writes a short summary that would fail validation. fromjson? skips a
  # partially written trailing line.
  jq -rnR '
    [inputs | fromjson? | .message.content? | arrays | .[] | objects
     | select(.type == "tool_use" and .name == "SubagentHandback") | .input.message | strings]
    | if length > 0 then "x" + last else empty end
  ' "$file" 2>/dev/null
}

HANDBACK=$(printf '%s' "$INPUT" | jq -r '(.tool_response | objects | .handback | strings) // empty' 2>/dev/null)

# Withheld: the harness delivered no report, so there is nothing to validate and nothing a
# re-invoke would fix. Say so; never block.
if [ "$HANDBACK" = "withheld" ]; then
  note "Hook H6 (reasonable-agents): ${SUBAGENT_TYPE} reported via SubagentHandback, but the harness withheld the report, so structural validation did NOT run. This is not a block and no re-invoke is expected."
  exit 0
fi

# Source A: hand-back report carried in the payload. Present-but-empty is validated (and so
# blocks); only an absent report falls through.
SOURCE="inline"
HAS_HANDBACK_REPORT=$(printf '%s' "$INPUT" | jq -r '
  .tool_response
  | if type == "object" and (.handbackReport | type) == "object"
       and (.handbackReport.text | type) == "string" then "yes" else "no" end
' 2>/dev/null)

if [ "$HAS_HANDBACK_REPORT" = "yes" ]; then
  SOURCE="handback"
  RESPONSE_TEXT=$(printf '%s' "$INPUT" | jq -r '.tool_response.handbackReport.text' 2>/dev/null)
else
  # Inline text. Coalesce string / {text}-array / object-with-.content-or-.text; any
  # element that is not a string or a {text: string} object contributes nothing rather
  # than erroring jq (an error here would empty the text and silently pass).
  RESPONSE_TEXT=$(printf '%s' "$INPUT" | jq -r '
    def txt:
      if type == "string" then .
      elif type == "array" then
        map(if type == "string" then .
            elif type == "object" and (.text | type) == "string" then .text
            else "" end) | join("\n")
      else "" end;
    .tool_response | if type == "object" then ((.content // .text // "") | txt) else txt end
  ' 2>/dev/null)

  # Hand-back pointer: short (or empty) text AND (any .handback value OR the harness pointer
  # sentence anywhere in it, which also covers a pointer behind a short leading harness
  # note). The length cap (characters) means a real report is always validated, never
  # downgraded; empty text with no .handback stays the silent async_launched pass below.
  IS_POINTER=0
  if [ "${#RESPONSE_TEXT}" -le 512 ]; then
    [ -n "$HANDBACK" ] && IS_POINTER=1
    case "$RESPONSE_TEXT" in *"This agent's report was delivered to you as a message from"*) IS_POINTER=1 ;; esac
  fi

  if [ "$IS_POINTER" -eq 1 ]; then
    # Source B: the subagent transcript. Unreachable → note, never a block.
    FOUND=$(subagent_handback)
    if [ -n "$FOUND" ]; then
      SOURCE="transcript"
      RESPONSE_TEXT="${FOUND#x}"
    else
      PATTERN_NAMES=$(jq -r '.required_patterns[]?.name | strings | "  - " + .' "$CONFIG_FILE" 2>/dev/null)
      note "Hook H6 (reasonable-agents): ${SUBAGENT_TYPE} returned its report via SubagentHandback, and neither the hook payload nor the subagent transcript exposed the report text, so structural validation did NOT run. This is not a block. Check the hand-back report for:
${PATTERN_NAMES}
If any are missing, re-invoke the reviewer per the feedback_template in ${CONFIG_FILE}."
      exit 0
    fi
  fi
fi

# Inline with no text → silent pass (covers async_launched background calls). A hand-back
# report that is present but empty is validated below, so it blocks.
[ "$SOURCE" = "inline" ] && [ -z "$RESPONSE_TEXT" ] && exit 0

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
  # Only grep exit 1 (no match) counts as missing. Exit 2 is a malformed regex in the
  # schema; a config error must fail open for that pattern, not block every run.
  RC=0; printf '%s' "$RESPONSE_TEXT" | grep -qE -- "$REGEX" 2>/dev/null || RC=$?
  [ "$RC" -eq 1 ] && MISSING="${MISSING}  - ${NAME}"$'\n'
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
  # Surface the gap as a note (stderr at exit 0 is invisible) but don't block again.
  note "$(printf 'Hook H6 (reasonable-agents): %s output still missing required elements, but the circuit-breaker has tripped (%d blocks this session), so this is not a block and no re-invoke is expected.\nMissing:\n%s' \
    "$SUBAGENT_TYPE" "$CURRENT" "$MISSING")"
  exit 0
fi

echo $((CURRENT + 1)) > "$COUNT_FILE" 2>/dev/null || exit 0   # fail open if the count can't be persisted

FEEDBACK=$(jq -r '.feedback_template // "Re-invoke the reviewer with an explicit instruction to begin its response with the required structural elements before addressing any caller-provided structure or questions."' "$CONFIG_FILE" 2>/dev/null)

printf 'Hook H6 (reasonable-agents): %s output failed structural validation (report source: %s).\n\nMissing required structural elements:\n%s\n%s\nTo disable: export REASONABLE_AGENTS_VALIDATE_REVIEWERS=0 (or REASONABLE_AGENTS_DISABLE=1).\n' \
  "$SUBAGENT_TYPE" "$SOURCE" "$MISSING" "$FEEDBACK" >&2
exit 2
