#!/usr/bin/env bats
# H6 — reviewer-output-validator.sh. Offline, hermetic, no API spend.
# HOME, CLAUDE_PLUGIN_DATA, CLAUDE_PLUGIN_ROOT are redirected to temp dirs; the shipped
# fixture validator and example validator are the real schemas under test.

setup() {
  ROOT="${BATS_TEST_DIRNAME}/.."
  H6="$ROOT/scripts/reviewer-output-validator.sh"
  TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/h6.XXXXXX")"
  export HOME="$TMP/home"; mkdir -p "$HOME"
  export CLAUDE_PLUGIN_DATA="$TMP/data"
  mkdir -p "$CLAUDE_PLUGIN_DATA/validators"
  # DATA-dir validator = the born-clean fixture schema (subagent_type trail-route-planning-reviewer).
  cp "$ROOT/fixtures/trail-route-planning-reviewer.json" "$CLAUDE_PLUGIN_DATA/validators/"
  unset CLAUDE_PLUGIN_ROOT 2>/dev/null || true

  # Well-formed reviewer output: Risk table + Bailout table + VERDICT.
  WELLFORMED="$(printf '%s\n' \
    '| Risk | Likelihood | Mitigation |' '|---|---|---|' '| Afternoon storms | High | Start before dawn |' \
    '' \
    '| Bailout | Trigger | Exit |' '|---|---|---|' '| Day 1 road crossing | Injury | Hike out north |' \
    '' \
    'VERDICT: GO')"

  # Malformed: omits ONLY the bailout/contingency table (keeps Risk + VERDICT).
  OMIT_BAILOUT="$(printf '%s\n' \
    '| Risk | Likelihood | Mitigation |' '|---|---|---|' '| Afternoon storms | High | Start before dawn |' \
    '' \
    'VERDICT: GO')"
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# $1 = subagent_type, $2 = response text, $3 = session_id (default sess-1).
payload() {
  jq -cn --arg st "$1" --arg rt "$2" --arg sid "${3:-sess-1}" \
    '{tool_input:{subagent_type:$st}, session_id:$sid, tool_response:$rt}'
}

@test "kill-switch master DISABLE=1 → silent pass even with malformed output" {
  run env REASONABLE_AGENTS_DISABLE=1 bash "$H6" <<< "$(payload trail-route-planning-reviewer "$OMIT_BAILOUT")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "kill-switch per-feature VALIDATE_REVIEWERS=0 → silent pass" {
  run env REASONABLE_AGENTS_VALIDATE_REVIEWERS=0 bash "$H6" <<< "$(payload trail-route-planning-reviewer "$OMIT_BAILOUT")"
  [ "$status" -eq 0 ]
}

@test "lookup DATA-hit: validator in DATA dir, malformed output → exit 2" {
  run bash "$H6" <<< "$(payload trail-route-planning-reviewer "$OMIT_BAILOUT")"
  [ "$status" -eq 2 ]
}

@test "lookup ROOT-fallback: no DATA validator, CLAUDE_PLUGIN_ROOT seeded, malformed → exit 2" {
  # example-reviewer has no DATA validator; the shipped validators/example-reviewer.json
  # under CLAUDE_PLUGIN_ROOT must be consulted. Seeding the temp ROOT proves the branch ran.
  run env CLAUDE_PLUGIN_ROOT="$ROOT" bash "$H6" <<< "$(payload example-reviewer "No required structure present.")"
  [ "$status" -eq 2 ]
}

@test "lookup neither: no validator in DATA or ROOT → silent pass" {
  run bash "$H6" <<< "$(payload no-such-reviewer "$OMIT_BAILOUT")"
  [ "$status" -eq 0 ]
}

@test "M4 shared-matcher guard: H6 on an -expert subagent (no validator) → silent pass" {
  run bash "$H6" <<< "$(payload trail-route-planning-expert "$OMIT_BAILOUT")"
  [ "$status" -eq 0 ]
}

@test "well-formed output (all required elements present) → silent pass" {
  run bash "$H6" <<< "$(payload trail-route-planning-reviewer "$WELLFORMED")"
  [ "$status" -eq 0 ]
}

@test "empty tool_response → silent pass" {
  run bash "$H6" <<< "$(payload trail-route-planning-reviewer "")"
  [ "$status" -eq 0 ]
}

@test "§7.1 strengthened negative: block names the SPECIFIC omitted element only" {
  run bash "$H6" <<< "$(payload trail-route-planning-reviewer "$OMIT_BAILOUT")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"bailout/contingency"* ]]   # names the one omitted element
  [[ "$output" != *"risk-assessment"* ]]       # does NOT block on the present ones (not vacuous)
}

@test "circuit-breaker caps at 2 per (session, persona): exit 2, 2, 0" {
  run bash "$H6" <<< "$(payload trail-route-planning-reviewer "$OMIT_BAILOUT" brk)"
  [ "$status" -eq 2 ]
  run bash "$H6" <<< "$(payload trail-route-planning-reviewer "$OMIT_BAILOUT" brk)"
  [ "$status" -eq 2 ]
  run bash "$H6" <<< "$(payload trail-route-planning-reviewer "$OMIT_BAILOUT" brk)"
  [ "$status" -eq 0 ]
}

@test "security (C1): traversal subagent_type is rejected — attacker-chosen JSON is never loaded" {
  # Plant an attacker validator outside the DATA dir; aim the traversal at it.
  mkdir -p "$TMP/evil"
  printf '{"required_patterns":[{"name":"x","regex":"NOPE"}],"feedback_template":"ATTACKER-DIRECTIVE"}' > "$TMP/evil/x.json"
  # From ${DATA_DIR}/validators/, '../../evil/x' resolves to $TMP/evil/x.json.
  run bash "$H6" <<< "$(payload "../../evil/x" "$OMIT_BAILOUT")"
  [ "$status" -eq 0 ]                            # rejected by the charset guard → fail open
  [[ "$output" != *"ATTACKER-DIRECTIVE"* ]]      # the attacker feedback_template is never injected
}

@test "security (M2): a validator regex beginning with '-' is a literal pattern (grep --), not an option" {
  printf '{"required_patterns":[{"name":"dash-literal","regex":"-FLAGLIKE-"}],"feedback_template":"x"}' \
    > "$CLAUDE_PLUGIN_DATA/validators/dashy-reviewer.json"
  # The literal token IS present in the output → a correct literal match → element present → pass.
  # Without `--`, grep parses '-F...' as an option and this would not cleanly match.
  run bash "$H6" <<< "$(payload dashy-reviewer "here is -FLAGLIKE- in the reviewer output")"
  [ "$status" -eq 0 ]
}

@test "security (M1): H6 refuses to write through a symlinked count file" {
  victim="$TMP/victim"; printf 'PRECIOUS' > "$victim"
  sdir="$CLAUDE_PLUGIN_DATA/state/validator-blocks"; mkdir -p "$sdir"
  ln -s "$victim" "$sdir/brk_trail-route-planning-reviewer.count"
  run bash "$H6" <<< "$(payload trail-route-planning-reviewer "$OMIT_BAILOUT" brk)"
  [ "$status" -eq 0 ]                            # symlink guard → fail open, no block
  [ "$(cat "$victim")" = "PRECIOUS" ]            # victim NOT clobbered through the symlink
}
