#!/usr/bin/env bats
# H6 — reviewer-output-validator.sh. Offline, hermetic, no API spend.
# HOME, CLAUDE_PLUGIN_DATA, CLAUDE_PLUGIN_ROOT are redirected to temp dirs; the shipped
# fixture validator and example validator are the real schemas under test.
#
# Hand-back cases derive their payloads from tests/fixtures/h6-pointer-only.json, a
# synthetic PostToolUse:Agent payload modeled on the CLI 2.1.281 hand-back shape (pointer
# in .content, report elsewhere), with the .handback enum taken from the 2.1.284 schema.

bats_require_minimum_version 1.5.0

setup() {
  ROOT="${BATS_TEST_DIRNAME}/.."
  H6="$ROOT/scripts/reviewer-output-validator.sh"
  FX="${BATS_TEST_DIRNAME}/fixtures/h6-pointer-only.json"
  TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/h6.XXXXXX")"
  export HOME="$TMP/home"; mkdir -p "$HOME"
  export CLAUDE_PLUGIN_DATA="$TMP/data"
  mkdir -p "$CLAUDE_PLUGIN_DATA/validators"
  # DATA-dir validator = the born-clean fixture schema (subagent_type trail-route-planning-reviewer).
  cp "$ROOT/fixtures/trail-route-planning-reviewer.json" "$CLAUDE_PLUGIN_DATA/validators/"
  unset CLAUDE_PLUGIN_ROOT 2>/dev/null || true
  # An ambient kill-switch export would turn every case below into a false pass.
  unset REASONABLE_AGENTS_DISABLE REASONABLE_AGENTS_VALIDATE_REVIEWERS 2>/dev/null || true

  PERSONA="trail-route-planning-reviewer"
  DATA_CFG="$CLAUDE_PLUGIN_DATA/validators/${PERSONA}.json"
  STATE="$CLAUDE_PLUGIN_DATA/state/validator-blocks"   # where H6 keeps its breaker counts
  AID="a1b2c3d4e5f6a7b8"                                # agentId in the fixture

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

# Run H6 with stdout ($output) and stderr ($stderr) kept apart. The kill switches are
# stripped from the child env; per-test env goes as NAME=VALUE args after the payload.
h6() {
  local p="$1"; shift
  run --separate-stderr env -u REASONABLE_AGENTS_DISABLE -u REASONABLE_AGENTS_VALIDATE_REVIEWERS \
    "$@" bash "$H6" <<< "$p"
}

# Derive a payload from the hand-back fixture with a jq filter; extra jq args pass through.
pay() { local f="$1"; shift; jq -c "$@" "$f" "$FX"; }

# The run was the non-blocking note: exit 0 + a PostToolUse additionalContext containing $1.
assert_note() {
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -qF -- "$1"
}

# Write a subagent transcript for agentId $1 beside $TMP/proj/sess.jsonl: one
# SubagentHandback call per remaining arg (its message), then the short post-hand-back
# summary a real subagent writes (which alone would fail validation), then a torn last line.
TPATH_FILTER='.transcript_path = $t'
subagent_transcript() {
  local id="$1" dir="$TMP/proj/sess/subagents" m; shift
  mkdir -p "$dir"; : > "$TMP/proj/sess.jsonl"
  {
    for m in "$@"; do
      jq -cn --arg m "$m" '{type:"assistant", message:{role:"assistant", content:[{type:"tool_use", id:"t1", name:"SubagentHandback", input:{message:$m}}]}}'
    done
    jq -cn '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:"I sent the review back to you. VERDICT: GO"}]}}'
    printf '{"type":"assistant","message":{"content":[{"type":"te'
  } > "$dir/agent-${id}.jsonl"
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

@test "circuit-breaker caps at 2 per (session, persona): exit 2, 2, then 0 with a visible note" {
  run bash "$H6" <<< "$(payload trail-route-planning-reviewer "$OMIT_BAILOUT" brk)"
  [ "$status" -eq 2 ]
  run bash "$H6" <<< "$(payload trail-route-planning-reviewer "$OMIT_BAILOUT" brk)"
  [ "$status" -eq 2 ]
  run --separate-stderr bash "$H6" <<< "$(payload trail-route-planning-reviewer "$OMIT_BAILOUT" brk)"
  assert_note "circuit-breaker has tripped"   # surfaced to Claude, not lost on stderr
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

# ---------- hand-back pointer, report unreachable → note, never a block ----------

@test "hand-back: pointer-only fixture, no transcript → note naming the patterns and validator, no state" {
  h6 "$(jq -c . "$FX")"
  assert_note "did NOT run"
  assert_note "bailout/contingency"
  assert_note "$DATA_CFG"                        # cites the resolved validator, not a fixed path
  [ -z "$stderr" ]
  [ ! -d "$CLAUDE_PLUGIN_DATA/state" ]
}

@test "hand-back: pointer sentence without the handback field → note" {
  h6 "$(pay 'del(.tool_response.handback)')"
  assert_note "did NOT run"
}

@test "hand-back: pointer as a bare-string tool_response → note" {
  h6 "$(pay '.tool_response = .tool_response.content[0].text')"
  assert_note "did NOT run"
}

@test "hand-back: pointer as a {text}-array tool_response → note" {
  h6 "$(pay '.tool_response = .tool_response.content')"
  assert_note "did NOT run"
}

@test "hand-back: flagged pointer (SECURITY WARNING variant) → note" {
  ptr="This agent's report was delivered to you as a message from \"${AID}\" (its SubagentHandback call), under a SECURITY WARNING from auto mode — the warning above the report says why. Read it there; it is not repeated here."
  h6 "$(pay '.tool_response.handback = "flagged" | .tool_response.content = [{type:"text", text:$p}]' --arg p "$ptr")"
  assert_note "did NOT run"
}

@test "hand-back: pointer behind a short leading harness note (no handback field) → note" {
  h6 "$(pay 'del(.tool_response.handback) | .tool_response.content = [{type:"text", text:"[harness: 1 note]"}] + .tool_response.content')"
  assert_note "did NOT run"
}

@test "hand-back: any handback value marks a pointer ('flagged', reworded text, no pointer sentence) → note" {
  h6 "$(pay '.tool_response.handback = "flagged" | .tool_response.content = [{type:"text", text:"Report delivered via hand-back; see the message."}]')"
  assert_note "did NOT run"
}

@test "hand-back: handback set, empty content, no report → note, not a silent pass" {
  h6 "$(pay '.tool_response.content = []')"
  assert_note "did NOT run"
}

@test "hand-back: withheld report → 'withheld' note, exit 0, no state" {
  h6 "$(pay '.tool_response.handback = "withheld" | .tool_response.content = [{type:"text", text:"No report was delivered."}]')"
  assert_note "withheld the report"
  [ ! -d "$CLAUDE_PLUGIN_DATA/state" ]
}

@test "hand-back: withheld wins over a handbackReport (never block on a withheld report)" {
  h6 "$(pay '.tool_response.handback = "withheld" | .tool_response.handbackReport = {text: $r}' --arg r "$OMIT_BAILOUT")"
  assert_note "withheld the report"
  [ ! -d "$CLAUDE_PLUGIN_DATA/state" ]
}

# ---------- source A: handbackReport.text in the payload ----------

@test "hand-back: handbackReport complete → fully silent pass" {
  h6 "$(pay '.tool_response.handbackReport = {text: $r}' --arg r "$WELLFORMED")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "hand-back: handbackReport deficient → exit 2 naming only the missing element and the source" {
  h6 "$(pay '.tool_response.handbackReport = {text: $r}' --arg r "$OMIT_BAILOUT")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"bailout/contingency"* ]]
  [[ "$stderr" != *"risk-assessment"* ]]
  [[ "$stderr" == *"report source: handback"* ]]
  [[ "$stderr" == *"REASONABLE_AGENTS_VALIDATE_REVIEWERS=0"* ]]   # the block names its off-switch
}

@test "hand-back: handbackReport present but empty → exit 2 (not a silent pass)" {
  h6 "$(pay '.tool_response.handbackReport = {text: ""}')"
  [ "$status" -eq 2 ]
}

# ---------- source B: the subagent transcript ----------

@test "hand-back transcript: complete hand-back → pass (reads SubagentHandback, not the trailing summary)" {
  subagent_transcript "$AID" "$WELLFORMED"
  h6 "$(pay "$TPATH_FILTER" --arg t "$TMP/proj/sess.jsonl")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hand-back transcript: deficient hand-back → exit 2 from source transcript" {
  subagent_transcript "$AID" "$OMIT_BAILOUT"
  h6 "$(pay "$TPATH_FILTER" --arg t "$TMP/proj/sess.jsonl")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"report source: transcript"* ]]
  [[ "$stderr" == *"bailout/contingency"* ]]
  [[ "$stderr" != *"risk-assessment"* ]]        # validated the hand-back, not the summary
}

@test "hand-back transcript: empty hand-back message → exit 2 (empty report is not 'no report')" {
  subagent_transcript "$AID" ""
  h6 "$(pay "$TPATH_FILTER" --arg t "$TMP/proj/sess.jsonl")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"report source: transcript"* ]]
}

@test "hand-back transcript: two hand-backs → the LAST one is validated" {
  subagent_transcript "$AID" "$OMIT_BAILOUT" "$WELLFORMED"
  h6 "$(pay "$TPATH_FILTER" --arg t "$TMP/proj/sess.jsonl")"
  [ "$status" -eq 0 ]
  subagent_transcript "$AID" "$WELLFORMED" "$OMIT_BAILOUT"
  h6 "$(pay "$TPATH_FILTER" --arg t "$TMP/proj/sess.jsonl")"
  [ "$status" -eq 2 ]
}

@test "hand-back transcript: a symlinked transcript file is refused → note" {
  subagent_transcript "elsewhere" "$WELLFORMED"
  ln -s "$TMP/proj/sess/subagents/agent-elsewhere.jsonl" "$TMP/proj/sess/subagents/agent-${AID}.jsonl"
  h6 "$(pay "$TPATH_FILTER" --arg t "$TMP/proj/sess.jsonl")"
  assert_note "did NOT run"
}

@test "hand-back transcript: traversal in agentId cannot escape the subagents dir → note" {
  mkdir -p "$TMP/proj/sess/subagents/agent-"
  # Unvalidated, agent-/../../../evil.jsonl resolves to $TMP/proj/evil.jsonl.
  jq -cn --arg m "$WELLFORMED" '{message:{content:[{type:"tool_use", name:"SubagentHandback", input:{message:$m}}]}}' > "$TMP/proj/evil.jsonl"
  : > "$TMP/proj/sess.jsonl"
  h6 "$(pay "$TPATH_FILTER"' | .tool_response.agentId = "/../../../evil"' --arg t "$TMP/proj/sess.jsonl")"
  assert_note "did NOT run"
}

@test "hand-back transcript: an out-of-charset agentId is rejected, not stripped → note" {
  # Stripping 'a1b2-c3' to 'a1b2c3' would load this planted transcript and pass.
  subagent_transcript "a1b2c3" "$WELLFORMED"
  h6 "$(pay "$TPATH_FILTER"' | .tool_response.agentId = "a1b2-c3"' --arg t "$TMP/proj/sess.jsonl")"
  assert_note "did NOT run"
}

@test "hand-back transcript: relative transcript_path is ignored → note" {
  subagent_transcript "$AID" "$WELLFORMED"
  cd "$TMP"   # without the guard, proj/sess.jsonl would resolve to the planted transcript and pass
  h6 "$(pay '.transcript_path = "proj/sess.jsonl"')"
  assert_note "did NOT run"
}

# ---------- a real report is never downgraded to the note ----------

@test "hand-back: handback=send with a long (>512 char) deficient inline report → exit 2, not a note" {
  long=""; for _ in 1 2 3 4 5 6 7 8; do long="${long}${OMIT_BAILOUT}"$'\n'; done
  [ "${#long}" -gt 512 ]
  h6 "$(pay '.tool_response.content = [{type:"text", text:$r}]' --arg r "$long")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"report source: inline"* ]]
}

# ---------- legacy inline shapes (behavior unchanged, jq coalesce hardened) ----------

@test "inline object {content:[{text}]} complete → silent pass" {
  h6 "$(pay '.tool_response = {content:[{type:"text", text:$r}]}' --arg r "$WELLFORMED")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "inline object {content:[{text}]} deficient → exit 2" {
  h6 "$(pay '.tool_response = {content:[{type:"text", text:$r}]}' --arg r "$OMIT_BAILOUT")"
  [ "$status" -eq 2 ]
}

@test "inline .content as a deficient string → exit 2 (not a jq error that passes silently)" {
  h6 "$(pay '.tool_response = {content:$r}' --arg r "$OMIT_BAILOUT")"
  [ "$status" -eq 2 ]
}

@test "inline .content array with non-object elements → still validated, exit 2" {
  h6 "$(pay '.tool_response = {content:[1, null, {type:"text", text:$r}]}' --arg r "$OMIT_BAILOUT")"
  [ "$status" -eq 2 ]
}

@test "async_launched (no content) → silent pass" {
  h6 "$(pay '.tool_response = {status:"async_launched", agentId:"a1"}')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------- opt-in, ROOT lookup, breaker, fail-open ----------

@test "hand-back: persona without a validator → silent pass even on a pointer" {
  h6 "$(pay '.tool_input.subagent_type = "general-purpose"')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hand-back ROOT-fallback: no DATA validator, deficient handbackReport → exit 2" {
  rm "$DATA_CFG"
  h6 "$(pay '.tool_response.handbackReport = {text: $r}' --arg r "$OMIT_BAILOUT")" CLAUDE_PLUGIN_ROOT="$ROOT"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"report source: handback"* ]]
}

@test "hand-back ROOT-fallback: pointer note cites the shipped validator under CLAUDE_PLUGIN_ROOT" {
  rm "$DATA_CFG"
  h6 "$(jq -c . "$FX")" CLAUDE_PLUGIN_ROOT="$ROOT"
  assert_note "$ROOT/validators/${PERSONA}.json"   # proves the ROOT branch loaded
}

@test "hand-back: first deficient report blocks and increments the counter" {
  h6 "$(pay '.tool_response.handbackReport = {text: $r}' --arg r "$OMIT_BAILOUT")"
  [ "$status" -eq 2 ]
  [ "$(cat "$STATE/fixture-session_${PERSONA}.count")" = "1" ]
}

@test "hand-back: kill switch DISABLE=1 darkens H6 on a deficient report, no state" {
  h6 "$(pay '.tool_response.handbackReport = {text: $r}' --arg r "$OMIT_BAILOUT")" REASONABLE_AGENTS_DISABLE=1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -d "$CLAUDE_PLUGIN_DATA/state" ]
}

@test "hand-back: kill switch VALIDATE_REVIEWERS=0 darkens H6 on a deficient report, no state" {
  h6 "$(pay '.tool_response.handbackReport = {text: $r}' --arg r "$OMIT_BAILOUT")" REASONABLE_AGENTS_VALIDATE_REVIEWERS=0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -d "$CLAUDE_PLUGIN_DATA/state" ]
}

@test "malformed regex in the schema fails open for that pattern; valid patterns still enforce" {
  jq '.required_patterns += [{name:"broken pattern", regex:"("}]' "$DATA_CFG" > "$DATA_CFG.tmp"
  mv "$DATA_CFG.tmp" "$DATA_CFG"
  jq -e '.required_patterns[-1].regex == "("' "$DATA_CFG" >/dev/null   # precondition: it landed
  h6 "$(pay '.tool_response.handbackReport = {text: $r}' --arg r "$WELLFORMED")"
  [ "$status" -eq 0 ]
  h6 "$(pay '.tool_response.handbackReport = {text: $r}' --arg r "$OMIT_BAILOUT")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"bailout/contingency"* ]]
  [[ "$stderr" != *"broken pattern"* ]]
}
