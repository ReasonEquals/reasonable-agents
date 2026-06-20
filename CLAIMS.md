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
| Prompt-level enforcement alone was insufficient — harness enforcement exists because of measured failures. | [`docs/provenance.md`](docs/provenance.md) — sanitized account of the measured prompt-level failure that motivated H6. | **BACKED NOW** |
| Each of the 6 shipped starter-pack reviewers' natural output passes its own H6 schema (dogfooded through the H4 → reviewer → H6 chain). | [`bench/pack-dogfood/*.md`](bench/pack-dogfood/) — live `claude -p` runs: H4 fires (`rc=2`) on each expert, H6 passes (`rc=0`) on each reviewer's real output — plus `tests/pack.bats` (offline per-triple schema discrimination, both omission directions). This is one end-to-end pass per triple, **not** the k/n compliance rate in the row below. | **BACKED NOW** |
| The model complies with the injected directive at rate k/n (the run actually ends with the reviewer run / re-invoked). | `bench/live-pairing-demo.md` — n ≥ 10 clean-profile runs, compliance counted. | PENDING — live demo |
| Minting a triad costs ~$X and ~Y minutes. | `bench/mint-run.md` — measured, labeled, typical not best-case. | PENDING |

## Scope limits

- **Enforcement is model-mediated, not mechanical.** The hooks *inject a directive*; the model *complies*. We
  publish a measured compliance rate — we never claim review is "forced."
- **"Validated" = process-validated**, not a domain-accuracy benchmark and not a guarantee the expert is right.
- **Hooks fail open.** Any uncertainty (missing config, empty output, parse failure, even a missing
  dependency) → silent pass (exit 0). They reduce missed reviews; they are not a hard gate.
- **User-scope agents only.** Reviewer lookup is `~/.claude/agents/<stem>-reviewer.md`. Project-scope
  (`.claude/agents/`) pairs are not enforced in v0.1.
- **Cross-session dedup is best-effort** and can false-positive / false-negative across session boundaries.
  The dedup also assumes `[a-z0-9-]` agent names (the minting convention); a name with regex metacharacters
  could loosen the match.
- **Local CLI / desktop only.** Behavior in web/cloud Claude Code sessions is unverified.
- **Plugin-spec churn.** Hook payload shapes are coupled to Claude Code internals; CI runs weekly against the
  latest Claude Code to catch drift.
