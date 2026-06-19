# reasonable-agents

> **Status: pre-release (v0.1 — S0 skeleton).** This release scaffolds and installs the plugin, but the
> enforcement hooks ship as **fail-open no-ops** — they do nothing yet. The review-enforcement logic lands in
> the next release. Nothing here blocks your turn today. See [CLAIMS.md](CLAIMS.md) for exactly what is and
> isn't backed.

Harness-enforced adversarial review for Claude Code subagents.

**For Claude Code power users who build domain-expert agents and don't trust a persona's self-review,**
`reasonable-agents` is a plugin that — when complete — blocks the turn at the harness layer until the paired
skeptic has run and its output has passed a structural schema. Unlike static persona packs and validation-only
toolkits, the review isn't a file you hope the agent reads — the harness enforces it.

## The model: mint → enforce → verify

- **Mint** a domain-expert + adversarial-reviewer persona pair, grounded in a researched briefing.
- **Enforce** the pairing at the hook layer: after an `*-expert` subagent runs without its paired
  `*-reviewer`, a `PostToolUse` hook injects a directive to run the reviewer; a second hook validates the
  reviewer's output against a structural schema and injects a re-invoke directive on failure.
- **Verify** with shipped eval scaffolds.

Precision matters: compliance with an injected directive is **model-mediated, not mechanical**. This package
publishes a *measured compliance rate* — it does not claim review is "forced." See [CLAIMS.md](CLAIMS.md).

## What this isn't

- **Not an agent-observability / tracing product.** If you want traces, spans, and dashboards, use
  [Langfuse](https://langfuse.com). This plugin enforces a review *step*; it does not record or visualize runs.
- **No telemetry.** It sends nothing anywhere. See [SECURITY.md](SECURITY.md).
- **No SaaS, no account, no subscription.** It is a local plugin.
- **Not a domain-accuracy benchmark.** "Validated" here means *process-validated* (briefing-grounded,
  adversarially paired, schema-checked) — never a guarantee the expert is correct.

## Install

Requires Claude Code **2.1.109 or newer**.

```text
/plugin marketplace add ReasonEquals/reasonable-agents
/plugin install reasonable-agents@reasonable-agents
/plugin list
```

Or from a local clone:

```text
/plugin marketplace add /path/to/reasonable-agents
/plugin install reasonable-agents@reasonable-agents
```

## Configuration (v0.1: environment variables only)

Kill-switches are plain environment variables read by the hook scripts — export them in your shell before
launching Claude Code:

| Variable | Effect |
|---|---|
| `REASONABLE_AGENTS_DISABLE=1` | Master off — all enforcement hooks pass silently. |

> **Pre-release note:** in v0.1 the hooks are no-ops, so these switches are *reserved* — they take effect when
> enforcement lands in the next release. `userConfig` enable-time prompts and a persistent plugin data dir are
> a planned fast-follow once a wider Claude Code baseline supports them; v0.1 targets 2.1.109 and uses
> environment variables only.

## Scope limits

The hooks **fail open** (any uncertainty → silent pass), cover **user-scope agents only**
(`~/.claude/agents/`), and compliance is model-mediated. Full list in [CLAIMS.md](CLAIMS.md#scope-limits).

## License

[MIT](LICENSE).
