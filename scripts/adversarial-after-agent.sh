#!/usr/bin/env bash
# reasonable-agents — H4: adversarial-pairing enforcement (PostToolUse / Agent).
#
# After an `*-expert` subagent completes, if a paired `*-reviewer` agent exists in
# the user's agents dir and has NOT already run this session, inject a directive to
# run it before proceeding. Exit 2 = inject the directive as feedback; exit 0 =
# silent pass.
#
# Honest scope: this makes a missed review LESS likely by injecting a directive;
# compliance with that directive is model-mediated, not mechanical. Dedup is
# best-effort and keyed on the structured `subagent_type` field (a bare prose
# mention of the reviewer name does not count as a run). User-scope agents only
# (`$HOME/.claude/agents/`). The hook fails OPEN: any uncertainty exits 0.
#
# Config (env vars; default = enforce, never silently off if a var fails to set):
#   REASONABLE_AGENTS_DISABLE          master off-switch (1|true|yes|on|disabled)
#   REASONABLE_AGENTS_ENFORCE_PAIRING  per-feature; off-set (0|false|no|off|disabled)
#
# bash 3.2 compatible (macOS default).

set -u

# --- Kill-switch FIRST (must not depend on the machinery it gates) ----------------------
# Normalize, then test an explicit set; no positional `:-` cascade footgun. The master
# switch defaults OFF (enforce); the per-feature switch defaults ON (enforce). Drain stdin
# before exiting so an upstream writer never takes SIGPIPE.
_ra_norm() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'; }

case "$(_ra_norm "${REASONABLE_AGENTS_DISABLE:-off}")" in
  1|true|yes|on|disabled) cat >/dev/null 2>&1 || true; exit 0 ;;
esac
case "$(_ra_norm "${REASONABLE_AGENTS_ENFORCE_PAIRING:-on}")" in
  0|false|no|off|disabled) cat >/dev/null 2>&1 || true; exit 0 ;;
esac

INPUT="$(cat)"
SUBAGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# Only `*-expert` subagents trigger the pairing rule.
[[ "$SUBAGENT_TYPE" != *-expert ]] && exit 0

# Security: subagent_type is interpolated into the reviewer file path and the dedup regex
# below. Reject anything outside the minting namespace ([a-z0-9-]) so a crafted value
# cannot traverse the filesystem or inject regex metacharacters. A non-conforming type has
# no managed reviewer anyway -> fail open.
case "$SUBAGENT_TYPE" in *[!a-z0-9-]*) exit 0 ;; esac

REVIEWER="${SUBAGENT_TYPE%-expert}-reviewer"
REVIEWER_FILE="$HOME/.claude/agents/${REVIEWER}.md"

# No paired reviewer file for this expert — nothing to enforce.
[ ! -f "$REVIEWER_FILE" ] && exit 0

# Dedup on the STRUCTURED field: a real reviewer invocation serializes
# `"subagent_type":"<reviewer>"` (compact, on one JSONL line). A bare prose mention of
# the reviewer name does NOT match this — so a mention cannot suppress the directive.
# (Assumes `[a-z0-9-]` agent names, the minting convention; disclosed in CLAIMS.)
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  if grep -Eq -- "\"subagent_type\"[[:space:]]*:[[:space:]]*\"${REVIEWER}\"" "$TRANSCRIPT" 2>/dev/null; then
    exit 0
  fi
fi

printf 'Hook H4 (reasonable-agents): %s completed, but its paired reviewer (%s) has not run this session.\nPer the adversarial-pairing rule, pass the expert output to %s before proceeding.\nTo disable: export REASONABLE_AGENTS_ENFORCE_PAIRING=0 (or REASONABLE_AGENTS_DISABLE=1).\n' \
  "$SUBAGENT_TYPE" "$REVIEWER" "$REVIEWER" >&2
exit 2
