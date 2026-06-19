# CLAIMS

Receipts discipline: every published claim names a reproducible check. Best-case vs typical are separated;
estimated vs measured are labeled; scope limits are stated inline. **No telemetry, ever** (see
[SECURITY.md](SECURITY.md)).

This is a **pre-release (v0.1) skeleton.** Most of the product's claims are not yet backed, because the
enforcement and verification layers ship in later releases. The table marks each claim's status honestly —
making a claim before its receipt exists is the failure mode this file is designed to prevent.

| Claim | Receipt | Status |
|---|---|---|
| No personal data ships with this package. | `tests/contraband.sh` (the CI gate itself) + a pinned, non-identifying commit identity + a `git log` author check at build time. | **BACKED NOW** |
| An `*-expert` run without its paired `*-reviewer` triggers a blocking directive; measured reviewer-compliance rate = k/n. | `tests/h4.bats` (offline replay) + a live pairing demo (n ≥ 10, compliance counted). | PENDING — enforcement release |
| Non-conforming reviewer output triggers an injected re-invoke directive, capped per session (circuit breaker). | `tests/h6.bats`, including the circuit-breaker case. | PENDING — enforcement release |
| Prompt-level enforcement alone was insufficient — harness enforcement exists because of measured failures. | `docs/provenance.md` (sanitized reproduction). | PENDING |
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
- **Local CLI / desktop only.** Behavior in web/cloud Claude Code sessions is unverified.
- **Plugin-spec churn.** Hook payload shapes are coupled to Claude Code internals; CI runs weekly against the
  latest Claude Code to catch drift.
- **v0.1 hooks are no-ops.** This release ships fail-open placeholders; the enforcement logic lands in the
  next release.
