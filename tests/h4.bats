#!/usr/bin/env bats
# H4 — adversarial-after-agent.sh. Offline, hermetic, no API spend.
# Each test runs in its own subshell with HOME redirected to a fresh temp dir;
# payloads are built inline (no literal user paths in source → passes contraband).

setup() {
  H4="${BATS_TEST_DIRNAME}/../scripts/adversarial-after-agent.sh"
  TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/h4.XXXXXX")"
  export HOME="$TMP"
  mkdir -p "$HOME/.claude/agents"
  TRANSCRIPT="$TMP/transcript.jsonl"
  : > "$TRANSCRIPT"
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# Create the paired reviewer file so the fire path is reachable.
make_reviewer() {
  printf '%s\n' '---' 'name: trail-route-planning-reviewer' '---' 'reviewer body' \
    > "$HOME/.claude/agents/trail-route-planning-reviewer.md"
}

# $1 = subagent_type, $2 = transcript_path → compact JSON payload on stdin.
payload() {
  printf '{"tool_input":{"subagent_type":"%s"},"transcript_path":"%s"}' "$1" "$2"
}

@test "kill-switch master DISABLE=1 → silent pass even when it would otherwise fire" {
  make_reviewer
  run env REASONABLE_AGENTS_DISABLE=1 bash "$H4" <<< "$(payload trail-route-planning-expert "$TRANSCRIPT")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "kill-switch per-feature ENFORCE_PAIRING=0 → silent pass" {
  make_reviewer
  run env REASONABLE_AGENTS_ENFORCE_PAIRING=0 bash "$H4" <<< "$(payload trail-route-planning-expert "$TRANSCRIPT")"
  [ "$status" -eq 0 ]
}

@test "default (switches unset) + fire condition → exit 2 naming the reviewer" {
  make_reviewer
  run bash "$H4" <<< "$(payload trail-route-planning-expert "$TRANSCRIPT")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"trail-route-planning-reviewer"* ]]
}

@test "current agent is a -reviewer (not -expert) → silent pass (H4 ignores non-experts)" {
  make_reviewer
  run bash "$H4" <<< "$(payload trail-route-planning-reviewer "$TRANSCRIPT")"
  [ "$status" -eq 0 ]
}

@test "expert ran but no paired reviewer file exists → silent pass" {
  # deliberately no make_reviewer
  run bash "$H4" <<< "$(payload trail-route-planning-expert "$TRANSCRIPT")"
  [ "$status" -eq 0 ]
}

@test "mere-mention guard (MF5): reviewer named only in prose → still fires (exit 2)" {
  make_reviewer
  printf '%s\n' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"Run the \"trail-route-planning-reviewer\" agent next."}]}}' \
    > "$TRANSCRIPT"
  run bash "$H4" <<< "$(payload trail-route-planning-expert "$TRANSCRIPT")"
  [ "$status" -eq 2 ]
}

@test "dedup (MF5): reviewer already ran via structured subagent_type → silent pass" {
  make_reviewer
  # M1: serialized compact on one line, mirroring live CC transcript JSONL.
  printf '%s\n' \
    '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"trail-route-planning-reviewer"}}]}}' \
    > "$TRANSCRIPT"
  run bash "$H4" <<< "$(payload trail-route-planning-expert "$TRANSCRIPT")"
  [ "$status" -eq 0 ]
}

@test "security (L2): subagent_type with a regex metachar is rejected, not used in the dedup regex" {
  # Unsanitized, 'a.b-expert' would make the dedup pattern treat '.' as a wildcard.
  # A paired reviewer file exists, transcript is empty → without the charset guard this
  # would FIRE (exit 2); with the guard the non-namespace type is ignored (exit 0).
  printf '%s\n' '---' 'name: a.b-reviewer' '---' 'reviewer body' > "$HOME/.claude/agents/a.b-reviewer.md"
  run bash "$H4" <<< "$(payload "a.b-expert" "$TRANSCRIPT")"
  [ "$status" -eq 0 ]
}

@test "security (C1): traversal subagent_type is rejected before any path use → silent pass" {
  make_reviewer
  run bash "$H4" <<< "$(payload "../../../../etc/passwd-expert" "$TRANSCRIPT")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
