# reasonable-agents — technical writeup (DRAFT)

> **DRAFT.** Values marked `<PENDING>` are filled in after the live gate runs — do not cite them yet.

## The wedge: enforce the review, don't just ship the reviewer

Static persona packs ship a reviewer as a markdown file and hope the agent reads it. Validation
toolkits check a persona's structure but don't block on a missing review. `reasonable-agents` leads
with the part that is actually load-bearing: **a harness hook that blocks the turn until the paired
skeptic has run, and a second hook that checks the skeptic's output against a structural schema.**

Two `PostToolUse` / `Agent` hooks:

- **H4 — pairing enforcement.** After an `*-expert` subagent runs, if a paired `*-reviewer` exists in
  the user's agents dir and hasn't run this session, inject a directive to run it.
- **H6 — output validation.** After a reviewer runs, validate its output against a per-persona schema
  of required structural elements; on a miss, inject a re-invoke directive (circuit-breaker capped).

Both fail open. Compliance with an injected directive is **model-mediated, not mechanical** — so the
package publishes a *measured compliance rate*, never "forced." (See [CLAIMS.md](../CLAIMS.md),
[SECURITY.md](../SECURITY.md).)

## Receipts, not adjectives

Every claim names a check:

- The directive fires / the validator blocks → `tests/h4.bats`, `tests/h6.bats` (offline, no API spend).
- The validator discriminates on a *specific* missing element → the strengthened negative test in
  `tests/h6.bats` (asserts the block names the omitted element, not just "malformed").
- No personal data ships → `tests/contraband.sh` (also a CI job).
- Why harness enforcement exists at all → [docs/provenance.md](provenance.md) (the measured
  prompt-level failure that motivated H6).
- Live pairing-compliance rate → `<PENDING: n/N>` (measured on the fixture pair).

## The skeptic caught my own bugs

This package was built through adversarial review, and the review earned its keep twice on the hooks'
own design:

1. **Bare-string dedup.** The first H4 dedup matched the reviewer's name as a bare quoted string
   anywhere in the transcript. A reviewer merely *mentioned* in prose would have falsely counted as
   "already run," silently suppressing the directive. Fixed to match the **structured**
   `subagent_type` field — a mention no longer suppresses.
2. **Kill-switch `:-` cascade.** An early kill-switch used a positional `:-` default that could read
   as "off" on an empty value — enforcement silently disabled by a propagation glitch. Fixed to
   normalize + explicit set-match, default-enforce.

Neither was caught by writing the code; both were caught by running the skeptic against the plan.
That is the product, demonstrated on itself.

## What's not here (yet)

Minting, eval scaffolds, the factory loop, and a starter persona pack are later, demand-gated phases.
This release is the enforcement chain plus its tests and receipts. Phase 3 dogfood runs: `<PENDING>`.
