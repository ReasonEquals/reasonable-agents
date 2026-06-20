# Dogfood receipt — software-architecture-review

Built and validated through the plugin's own enforcement chain (H4 → reviewer → H6), live, in a clean
throwaway project. Receipt for the `software-architecture-review` triple shipped in `pack/`.

- **Date:** 2026-06-19
- **Model:** `claude-opus-4-8[1m]` (orchestrator + both subagents)
- **Task (generic, public-domain):** *design the architecture for a URL-shortener service handling 10,000
  redirects per second with per-link click analytics.*
- **Run:** headless `claude -p`, `num_turns=3`, `subtype=success`, `is_error=false`.

## The chain (ground truth: logger-wrapper side log)

```
hook=H4 subagent_type=software-architecture-review-expert    rc=2
hook=H6 subagent_type=software-architecture-review-expert    rc=0
hook=H4 subagent_type=software-architecture-review-reviewer  rc=0
hook=H6 subagent_type=software-architecture-review-reviewer  rc=0
```

1. **H4 fired on the expert (`rc=2`)** — the expert ran without its reviewer, so H4 injected the pairing
   directive.
2. H6 was a no-op on the expert (`rc=0`) — there is no validator for an `*-expert`.
3. The orchestrator complied and ran the reviewer; H4 was a no-op on it (`rc=0`, not an `*-expert`).
4. **H6 validated the reviewer's real output and passed (`rc=0`)** — the reviewer's *natural* output
   satisfied every required element of `validators/software-architecture-review-reviewer.json` on the first
   try (no re-invoke needed).

## What the reviewer produced (structural skeleton, verified contraband-clean)

```
| Concern | Severity | Quality attribute | Recommendation |
| Failure mode | Trigger | Blast radius | Mitigation |
VERDICT: REVISE
```

The two required tables (`Concern`, `Failure`) and the `VERDICT:` line are exactly what H6 checks — which is
why it passed silently.

## Scope / honesty

Compliance with the H4 directive is **model-mediated, not mechanical** (the model chose to run the reviewer
after the directive fired) — see [CLAIMS.md](../../CLAIMS.md). This shows the chain completing once,
end-to-end; it is **not** the live compliance-rate measurement (still PENDING). The full transcript lived in a
throwaway dir and is not committed; only these parsed, vetted fields are. Method + reproduction:
[README.md](README.md). Offline equivalent: `tests/pack.bats`.
