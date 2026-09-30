# CLAIMS

Receipts discipline: every published claim names a reproducible check. Best-case vs typical are separated;
estimated vs measured are labeled; scope limits are stated inline. **No telemetry, ever** (see
[SECURITY.md](SECURITY.md)).

This release ships the **enforcement chain** — the two hooks, their tests, and the receipts below. The table
marks each claim's status honestly — making a claim before its receipt exists is the failure mode this file is
designed to prevent. Note the deliberate split on H4: that the *directive fires* is mechanically provable
offline (BACKED); that the model then *complies* is a measured live rate (PENDING). Minting claims remain
PENDING.

| Claim | Receipt | Status |
|---|---|---|
| No personal data ships with this package. | `tests/contraband.sh` (the CI gate itself) + a pinned, non-identifying commit identity + a `git log` author check at build time. | **BACKED NOW** |
| An `*-expert` run without its paired `*-reviewer` triggers a blocking directive (exit 2). | `tests/h4.bats` — offline replay of the Agent payloads; asserts the directive fires, and stays silent on the kill-switch / no-reviewer-file / already-ran / mere-mention paths. | **BACKED NOW** |
| Non-conforming reviewer output triggers an injected re-invoke directive that names the missing element, capped per session (circuit breaker). | `tests/h6.bats` — DATA/ROOT lookup branches, the strengthened negative (the block names the *specific* omitted element, not just "malformed"), and the circuit-breaker cap. | **BACKED NOW** |
| On the Claude Code 2.1.28x hand-back shape (as modeled by the fixture), H6 validates the reviewer's actual report (`handbackReport.text`, else the subagent's last `SubagentHandback` message) rather than the short pointer left in `content`; an unreachable or withheld report yields a non-blocking note, not a block. (v0.1.1+) | `tests/h6.bats` hand-back cases, replayed offline from `tests/fixtures/h6-pointer-only.json`, a synthetic payload modeled on the 2.1.281 pointer shape (`handback` values from the 2.1.284 schema). Offline replay, not a live run. | **BACKED NOW** |
| The hand-back handling behaves the same on a live run through the installed plugin (payload emitted by Claude Code, not synthetic). | A live hand-back reviewer run against a marketplace install of v0.1.1, with the hook result captured in full: exit code, stderr, **and** stdout (the note travels on stdout; the side-log wrapper in [`bench/pack-dogfood/README.md`](bench/pack-dogfood/README.md) forwards only stderr and the exit code, so it needs extending first). | PENDING |
| Prompt-level enforcement alone was insufficient — harness enforcement exists because of measured failures. | [`docs/provenance.md`](docs/provenance.md) — sanitized account of the measured prompt-level failure that motivated H6. | **BACKED NOW** |
| Each of the 6 shipped starter-pack reviewers' natural output passes its own H6 schema (dogfooded through the H4 → reviewer → H6 chain). | [`bench/pack-dogfood/*.md`](bench/pack-dogfood/) — live `claude -p` runs: H4 fires (`rc=2`) on each expert, H6 passes (`rc=0`) on each reviewer's real output — plus `tests/pack.bats` (offline per-triple schema discrimination, both omission directions). This is one end-to-end pass per triple, **not** the k/n compliance rate in the row below. | **BACKED NOW** |
| The model complies with the injected directive — actually runs the reviewer — at a measured rate. | `bench/live-pairing-demo.md` — 10 neutral clean-profile fixture runs: the expert ran in 9, H4 fired 9/9, the model complied 9/9 (one run invoked no subagent). Model-mediated; published as measured. | **BACKED NOW** |
| Minting a triad costs ~$X and ~Y minutes. | `bench/mint-run.md` — measured, labeled, typical not best-case. | PENDING |

## Scope limits

- **Enforcement is model-mediated, not mechanical.** The hooks *inject a directive*; the model *complies*. We
  publish a measured compliance rate — we never claim review is "forced."
- **"Validated" = process-validated**, not a domain-accuracy benchmark and not a guarantee the expert is right.
- **Hooks fail open.** Any uncertainty (missing config, empty output, parse failure, even a missing
  dependency) → exit 0: silent, or a non-blocking note when H6 cannot see a hand-back report or its circuit
  breaker has tripped. They reduce missed reviews; they are not a hard gate. One deliberate exception: a
  hand-back that delivered an *empty* report is a deficient review, so H6 validates it and blocks
  (breaker-capped).
- **User-scope agents only.** Reviewer lookup is `~/.claude/agents/<stem>-reviewer.md`. Project-scope
  (`.claude/agents/`) pairs are not enforced in v0.1.
- **Cross-session dedup is best-effort** and can false-positive / false-negative across session boundaries.
  The dedup also assumes `[a-z0-9-]` agent names (the minting convention); a name with regex metacharacters
  could loosen the match.
- **Local CLI / desktop only.** Behavior in web/cloud Claude Code sessions is unverified.
- **Plugin-spec churn.** Hook payload shapes are coupled to Claude Code internals. Weekly CI runs `claude
  plugin validate` against the latest Claude Code, catching *manifest-schema* drift — but not payload-shape
  drift: the offline tests replay fixed payloads and CI invokes no live subagent. A silent payload change
  would make the hooks no-op (fail-open) with CI still green, so re-running `bench/live-pairing-demo.md` is
  the manual canary. The 2.1.28x hand-back change was exactly this kind of drift. H6's hand-back handling
  leans on three undocumented details: the `@internal` `handback` / `handbackReport` fields, the pointer
  sentence Claude Code writes into `content`, and the subagent-transcript layout
  (`<transcript>/subagents/agent-<agentId>.jsonl`). Drift in any of them degrades to the non-blocking note
  or, at worst, a breaker-capped block. The note rides `hookSpecificOutput.additionalContext`; whether the
  2.1.109 baseline honors that on PostToolUse is unverified. If it is ignored, the note is dropped silently
  (as the old stderr message was) and no exit code changes.
