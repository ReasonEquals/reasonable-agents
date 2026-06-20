#!/usr/bin/env bats
# pack.bats — schema-correctness tests for the 3 shipped starter-pack validators.
# Offline, hermetic, no API spend.
#
# Each test points CLAUDE_PLUGIN_ROOT at the repo so H6 resolves the REAL shipped
# validators/<stem>-reviewer.json via its ROOT-fallback branch — the exact path the
# installed plugin uses. HOME is redirected to a fresh temp dir and CLAUDE_PLUGIN_DATA is
# unset, so no DATA-dir validator can shadow the shipped one (a stray hit would make the
# negative tests pass for the wrong reason). Payloads are built inline (no literal user
# paths in source -> passes the contraband gate).
#
# Per triple this asserts: H4 fires on the expert; H6 passes well-formed output; and H6
# discriminates in BOTH omission directions — naming the omitted table and NOT the present
# one (the strengthened §7.1 non-vacuity property). The api omit-table-1 case doubles as the
# keyword-collision guard: a Facet table whose cells contain "Breaking"/"Non-breaking" but no
# Change table must still block on the missing Change table.

setup() {
  ROOT="${BATS_TEST_DIRNAME}/.."
  H4="$ROOT/scripts/adversarial-after-agent.sh"
  H6="$ROOT/scripts/reviewer-output-validator.sh"
  TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/pack.XXXXXX")"
  export HOME="$TMP/home"; mkdir -p "$HOME/.claude/agents"
  TRANSCRIPT="$TMP/transcript.jsonl"; : > "$TRANSCRIPT"
  unset CLAUDE_PLUGIN_DATA 2>/dev/null || true
  export CLAUDE_PLUGIN_ROOT="$ROOT"

  # --- software-architecture-review reviewer outputs ---
  SW_OK="$(printf '%s\n' \
    '| Concern | Severity | Quality attribute | Recommendation |' '|---|---|---|---|' '| Tight coupling | High | maintainability | anti-corruption layer |' \
    '' \
    '| Failure mode | Trigger | Blast radius | Mitigation |' '|---|---|---|---|' '| Cache stampede | cold start | read path | request coalescing |' \
    '' \
    'VERDICT: REVISE')"
  SW_OMIT_FAILURE="$(printf '%s\n' \
    '| Concern | Severity | Quality attribute | Recommendation |' '|---|---|---|---|' '| Tight coupling | High | maintainability | port/adapter |' \
    '' 'VERDICT: REVISE')"
  SW_OMIT_CONCERN="$(printf '%s\n' \
    '| Failure mode | Trigger | Blast radius | Mitigation |' '|---|---|---|---|' '| Cache stampede | cold start | read path | coalescing |' \
    '' 'VERDICT: REVISE')"

  # --- agent-and-prompt-design reviewer outputs ---
  AG_OK="$(printf '%s\n' \
    '| Weakness | Class | Trigger | Hardening |' '|---|---|---|---|' '| Unscoped tool access | over-trust | hostile file | allowlist |' \
    '' \
    '| Eval gap | What could regress | Proposed check |' '|---|---|---|' '| Over-refusal | benign inputs blocked | benign-prompt fixtures |' \
    '' \
    'VERDICT: REVISE')"
  AG_OMIT_EVAL="$(printf '%s\n' \
    '| Weakness | Class | Trigger | Hardening |' '|---|---|---|---|' '| Prompt injection | injection | untrusted text | delimit + instruct |' \
    '' 'VERDICT: REVISE')"
  AG_OMIT_WEAKNESS="$(printf '%s\n' \
    '| Eval gap | What could regress | Proposed check |' '|---|---|---|' '| Format drift | schema break | JSON-schema assertion |' \
    '' 'VERDICT: REVISE')"

  # --- api-contract-design reviewer outputs ---
  API_OK="$(printf '%s\n' \
    '| Change | Breaking? | Affected clients | Migration |' '|---|---|---|---|' '| Remove status field | Yes | mobile v1 | dual-write one release |' \
    '' \
    '| Facet | Specified? | Risk if unspecified |' '|---|---|---|' '| Pagination | No | unbounded responses |' \
    '' \
    'VERDICT: BREAKING')"
  API_OMIT_FACET="$(printf '%s\n' \
    '| Change | Breaking? | Affected clients | Migration |' '|---|---|---|---|' '| Add optional cursor | No | none | n/a |' \
    '' 'VERDICT: COMPATIBLE')"
  # Non-vacuity guard: a Facet table whose cells contain title-cased "Breaking"/"Non-breaking"
  # but NO Change table. The Change requirement must still register as missing.
  API_FACET_ONLY="$(printf '%s\n' \
    '| Facet | Specified? | Risk if unspecified |' '|---|---|---|' '| Error model | No | Breaking on 4xx without a schema |' '| Versioning | Partial | Non-breaking additions undocumented |' \
    '' 'VERDICT: REVISE')"

  # --- security-threat-modeling reviewer outputs ---
  SEC_OK="$(printf '%s\n' \
    '| Threat | STRIDE category | Entry point | Why missed |' '|---|---|---|---|' '| Token replay | Spoofing | session cookie | no expiry modeled |' \
    '' \
    '| Control gap | Exposed asset | Recommended mitigation |' '|---|---|---|' '| No login rate limit | credentials | lockout + backoff |' \
    '' \
    'VERDICT: HARDEN')"
  SEC_OMIT_CONTROL="$(printf '%s\n' \
    '| Threat | STRIDE category | Entry point | Why missed |' '|---|---|---|---|' '| Token replay | Spoofing | session cookie | no expiry modeled |' \
    '' 'VERDICT: HARDEN')"
  SEC_OMIT_THREAT="$(printf '%s\n' \
    '| Control gap | Exposed asset | Recommended mitigation |' '|---|---|---|' '| No login rate limit | credentials | lockout + backoff |' \
    '' 'VERDICT: HARDEN')"

  # --- test-strategy-design reviewer outputs ---
  TST_OK="$(printf '%s\n' \
    '| Coverage gap | Untested behaviour | Where to add it |' '|---|---|---|' '| Concurrent writes | lost updates | integration test |' \
    '' \
    '| Brittleness risk | Cause | Stabilization |' '|---|---|---|' '| Flaky e2e | real network calls | stub the boundary |' \
    '' \
    'VERDICT: REVISE')"
  TST_OMIT_BRITTLE="$(printf '%s\n' \
    '| Coverage gap | Untested behaviour | Where to add it |' '|---|---|---|' '| Concurrent writes | lost updates | integration test |' \
    '' 'VERDICT: REVISE')"
  TST_OMIT_COVERAGE="$(printf '%s\n' \
    '| Brittleness risk | Cause | Stabilization |' '|---|---|---|' '| Flaky e2e | real network calls | stub the boundary |' \
    '' 'VERDICT: REVISE')"

  # --- boss-fight-design reviewer outputs ---
  BOSS_OK="$(printf '%s\n' \
    '| Balance concern | Phase | Why unfair or trivial | Adjustment |' '|---|---|---|---|' '| Phase 2 burst | 2 | one-shot no tell | add a wind-up |' \
    '' \
    '| Exploit | How it trivializes the fight | Counter |' '|---|---|---|' '| Corner-camping | boss cannot path | add a gap-closer |' \
    '' \
    'VERDICT: TUNE')"
  BOSS_OMIT_EXPLOIT="$(printf '%s\n' \
    '| Balance concern | Phase | Why unfair or trivial | Adjustment |' '|---|---|---|---|' '| Phase 2 burst | 2 | one-shot no tell | add a wind-up |' \
    '' 'VERDICT: TUNE')"
  BOSS_OMIT_BALANCE="$(printf '%s\n' \
    '| Exploit | How it trivializes the fight | Counter |' '|---|---|---|' '| Corner-camping | boss cannot path | add a gap-closer |' \
    '' 'VERDICT: TUNE')"
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# Create the paired reviewer stub so H4's fire path is reachable for $1 = <stem>.
make_reviewer() {
  printf '%s\n' '---' "name: ${1}-reviewer" '---' 'reviewer body' \
    > "$HOME/.claude/agents/${1}-reviewer.md"
}

# H4 payload: $1 = subagent_type, $2 = transcript_path.
h4_payload() { jq -cn --arg st "$1" --arg tp "$2" '{tool_input:{subagent_type:$st}, transcript_path:$tp}'; }

# H6 payload: $1 = subagent_type, $2 = response text, $3 = session_id (default sess-1).
h6_payload() { jq -cn --arg st "$1" --arg rt "$2" --arg sid "${3:-sess-1}" '{tool_input:{subagent_type:$st}, session_id:$sid, tool_response:$rt}'; }

# ============================ software-architecture-review ============================

@test "software: H4 fires when the expert runs without its reviewer (exit 2, names reviewer)" {
  make_reviewer software-architecture-review
  run bash "$H4" <<< "$(h4_payload software-architecture-review-expert "$TRANSCRIPT")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"software-architecture-review-reviewer"* ]]
}

@test "software: H6 passes well-formed output via the shipped validator (ROOT-fallback)" {
  run bash "$H6" <<< "$(h6_payload software-architecture-review-reviewer "$SW_OK")"
  [ "$status" -eq 0 ]
}

@test "software: H6 omit Failure-mode -> blocks naming failure-mode-table, not concern-table (§7.1)" {
  run bash "$H6" <<< "$(h6_payload software-architecture-review-reviewer "$SW_OMIT_FAILURE")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"failure-mode-table"* ]]
  [[ "$output" != *"concern-table"* ]]
}

@test "software: H6 omit Concern -> blocks naming concern-table, not failure-mode-table (mirror)" {
  run bash "$H6" <<< "$(h6_payload software-architecture-review-reviewer "$SW_OMIT_CONCERN")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"concern-table"* ]]
  [[ "$output" != *"failure-mode-table"* ]]
}

# ============================ agent-and-prompt-design ============================

@test "agent: H4 fires when the expert runs without its reviewer (exit 2, names reviewer)" {
  make_reviewer agent-and-prompt-design
  run bash "$H4" <<< "$(h4_payload agent-and-prompt-design-expert "$TRANSCRIPT")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"agent-and-prompt-design-reviewer"* ]]
}

@test "agent: H6 passes well-formed output via the shipped validator (ROOT-fallback)" {
  run bash "$H6" <<< "$(h6_payload agent-and-prompt-design-reviewer "$AG_OK")"
  [ "$status" -eq 0 ]
}

@test "agent: H6 omit Eval-gap -> blocks naming eval-gap-table, not weakness-table (§7.1)" {
  run bash "$H6" <<< "$(h6_payload agent-and-prompt-design-reviewer "$AG_OMIT_EVAL")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"eval-gap-table"* ]]
  [[ "$output" != *"weakness-table"* ]]
}

@test "agent: H6 omit Weakness -> blocks naming weakness-table, not eval-gap-table (mirror)" {
  run bash "$H6" <<< "$(h6_payload agent-and-prompt-design-reviewer "$AG_OMIT_WEAKNESS")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"weakness-table"* ]]
  [[ "$output" != *"eval-gap-table"* ]]
}

# ============================ api-contract-design ============================

@test "api: H4 fires when the expert runs without its reviewer (exit 2, names reviewer)" {
  make_reviewer api-contract-design
  run bash "$H4" <<< "$(h4_payload api-contract-design-expert "$TRANSCRIPT")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"api-contract-design-reviewer"* ]]
}

@test "api: H6 passes well-formed output via the shipped validator (ROOT-fallback)" {
  run bash "$H6" <<< "$(h6_payload api-contract-design-reviewer "$API_OK")"
  [ "$status" -eq 0 ]
}

@test "api: H6 omit Facet -> blocks naming facet-coverage-table, not compatibility-change-table (§7.1)" {
  run bash "$H6" <<< "$(h6_payload api-contract-design-reviewer "$API_OMIT_FACET")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"facet-coverage-table"* ]]
  [[ "$output" != *"compatibility-change-table"* ]]
}

@test "api: H6 — Facet table with 'Breaking' cells but no Change table still blocks (non-vacuity + mirror)" {
  # Must-fix #1: 'Breaking'/'Non-breaking' in Facet cells must NOT satisfy the Change table.
  run bash "$H6" <<< "$(h6_payload api-contract-design-reviewer "$API_FACET_ONLY")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"compatibility-change-table"* ]]
  [[ "$output" != *"facet-coverage-table"* ]]
}

# ============================ security-threat-modeling ============================

@test "security: H4 fires when the expert runs without its reviewer (exit 2, names reviewer)" {
  make_reviewer security-threat-modeling
  run bash "$H4" <<< "$(h4_payload security-threat-modeling-expert "$TRANSCRIPT")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"security-threat-modeling-reviewer"* ]]
}

@test "security: H6 passes well-formed output via the shipped validator (ROOT-fallback)" {
  run bash "$H6" <<< "$(h6_payload security-threat-modeling-reviewer "$SEC_OK")"
  [ "$status" -eq 0 ]
}

@test "security: H6 omit Control-gap -> blocks naming control-gap-table, not missed-threat-table (§7.1)" {
  run bash "$H6" <<< "$(h6_payload security-threat-modeling-reviewer "$SEC_OMIT_CONTROL")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"control-gap-table"* ]]
  [[ "$output" != *"missed-threat-table"* ]]
}

@test "security: H6 omit Threat -> blocks naming missed-threat-table, not control-gap-table (mirror)" {
  run bash "$H6" <<< "$(h6_payload security-threat-modeling-reviewer "$SEC_OMIT_THREAT")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missed-threat-table"* ]]
  [[ "$output" != *"control-gap-table"* ]]
}

# ============================ test-strategy-design ============================

@test "test-strategy: H4 fires when the expert runs without its reviewer (exit 2, names reviewer)" {
  make_reviewer test-strategy-design
  run bash "$H4" <<< "$(h4_payload test-strategy-design-expert "$TRANSCRIPT")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"test-strategy-design-reviewer"* ]]
}

@test "test-strategy: H6 passes well-formed output via the shipped validator (ROOT-fallback)" {
  run bash "$H6" <<< "$(h6_payload test-strategy-design-reviewer "$TST_OK")"
  [ "$status" -eq 0 ]
}

@test "test-strategy: H6 omit Brittleness -> blocks naming brittleness-table, not coverage-gap-table (§7.1)" {
  run bash "$H6" <<< "$(h6_payload test-strategy-design-reviewer "$TST_OMIT_BRITTLE")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"brittleness-table"* ]]
  [[ "$output" != *"coverage-gap-table"* ]]
}

@test "test-strategy: H6 omit Coverage -> blocks naming coverage-gap-table, not brittleness-table (mirror)" {
  run bash "$H6" <<< "$(h6_payload test-strategy-design-reviewer "$TST_OMIT_COVERAGE")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"coverage-gap-table"* ]]
  [[ "$output" != *"brittleness-table"* ]]
}

# ============================ boss-fight-design ============================

@test "boss-fight: H4 fires when the expert runs without its reviewer (exit 2, names reviewer)" {
  make_reviewer boss-fight-design
  run bash "$H4" <<< "$(h4_payload boss-fight-design-expert "$TRANSCRIPT")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"boss-fight-design-reviewer"* ]]
}

@test "boss-fight: H6 passes well-formed output via the shipped validator (ROOT-fallback)" {
  run bash "$H6" <<< "$(h6_payload boss-fight-design-reviewer "$BOSS_OK")"
  [ "$status" -eq 0 ]
}

@test "boss-fight: H6 omit Exploit -> blocks naming exploit-table, not balance-table (§7.1)" {
  run bash "$H6" <<< "$(h6_payload boss-fight-design-reviewer "$BOSS_OMIT_EXPLOIT")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"exploit-table"* ]]
  [[ "$output" != *"balance-table"* ]]
}

@test "boss-fight: H6 omit Balance -> blocks naming balance-table, not exploit-table (mirror)" {
  run bash "$H6" <<< "$(h6_payload boss-fight-design-reviewer "$BOSS_OMIT_BALANCE")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"balance-table"* ]]
  [[ "$output" != *"exploit-table"* ]]
}

# ============================ lookup control ============================

@test "control: no shipped-validator path (CLAUDE_PLUGIN_ROOT unset, no DATA validator) -> fail-open pass" {
  # Proves the exit-2 results above genuinely come from the shipped validators via ROOT-fallback,
  # not a stray DATA-dir hit: remove the only lookup path and malformed output must pass silently.
  run env -u CLAUDE_PLUGIN_ROOT bash "$H6" <<< "$(h6_payload software-architecture-review-reviewer "$SW_OMIT_FAILURE")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
