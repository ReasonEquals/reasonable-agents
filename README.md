# reasonable-agents

> **Status: enforcement chain (v0.1).** The two enforcement hooks — H4 (expert→reviewer pairing) and H6
> (reviewer-output validation) — are live and covered by an offline test suite. A small born-clean starter
> persona pack ships in [`pack/`](pack/); minting and eval scaffolds are later, demand-gated phases. Local
> Claude Code CLI / desktop. See [CLAIMS.md](CLAIMS.md) for exactly what is and isn't backed.

Harness-enforced adversarial review for Claude Code subagents.

**For Claude Code power users who build domain-expert agents and don't trust a persona's self-review,**
`reasonable-agents` is a plugin that injects a blocking directive at the harness layer when an `*-expert`
subagent runs without its paired skeptic, then validates the skeptic's output against a structural schema.
Unlike static persona packs and validation-only toolkits, the review isn't a file you hope the agent reads —
the harness drives it. (Compliance with the directive is model-mediated, not mechanical — see
[CLAIMS.md](CLAIMS.md).)

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

## Quickstart — watch it block (≈ 2 minutes)

This uses the bundled fixture pair in `fixtures/` to demonstrate enforcement end-to-end. From a clone of this
repo:

```bash
# 1. Install the plugin from your local clone.
claude plugin marketplace add .
claude plugin install reasonable-agents@reasonable-agents

# 2. Copy the fixture expert + reviewer into your user agents dir.
mkdir -p ~/.claude/agents
cp fixtures/trail-route-planning-expert.md   ~/.claude/agents/
cp fixtures/trail-route-planning-reviewer.md ~/.claude/agents/

# 3. Copy the fixture's validator schema where H6 looks for it.
mkdir -p ~/.claude/state/reasonable-agents/validators
cp fixtures/trail-route-planning-reviewer.json ~/.claude/state/reasonable-agents/validators/
```

Then, in Claude Code:

1. Ask: **"Use the trail-route-planning-expert subagent to plan a 3-day backpacking loop."** When the expert
   finishes, **H4 fires** — a directive tells Claude to run the paired `trail-route-planning-reviewer` before
   continuing.
2. Let Claude run the reviewer. If the reviewer's output omits a required element (a Risk table, a Bailout
   table, or a `VERDICT:` line), **H6 fires** a re-invoke directive naming the missing element; once the output
   is well-formed, H6 passes silently.

Turn it off any time with `export REASONABLE_AGENTS_DISABLE=1`. To undo the demo, delete the three files you
copied.

> **Editing a hook script?** Plugin hooks are registered at install time, so a source edit needs a reload:
> `claude plugin uninstall reasonable-agents@reasonable-agents && claude plugin install reasonable-agents@reasonable-agents`.

## Starter persona pack

Six ready-to-use expert + reviewer + validator triples ship in [`pack/`](pack/) —
`software-architecture-review`, `agent-and-prompt-design`, `api-contract-design`, `security-threat-modeling`,
`test-strategy-design`, and `boss-fight-design`. They are born-clean and
generic (authored from public domain knowledge, not extracted from anyone's config), and each was built and
validated through this plugin's own enforcement chain — see the receipts in
[`bench/pack-dogfood/`](bench/pack-dogfood/). Copy a triple's expert + reviewer into `~/.claude/agents/`; its
validator already ships in `validators/` and H6 finds it automatically. Details: [`pack/README.md`](pack/README.md).

## Configuration (environment variables only)

Kill-switches are plain environment variables read at the top of each hook script — export them in your shell
before launching Claude Code. The default is always **enforce** (a variable that fails to propagate cannot
silently turn enforcement off).

| Variable | Effect |
|---|---|
| `REASONABLE_AGENTS_DISABLE` | Master off-switch — set to `1`/`true`/`yes`/`on` to disable both hooks. |
| `REASONABLE_AGENTS_ENFORCE_PAIRING` | Set to `0`/`false`/`off` to disable H4 (pairing) only. Default on. |
| `REASONABLE_AGENTS_VALIDATE_REVIEWERS` | Set to `0`/`false`/`off` to disable H6 (output validation) only. Default on. |

> `userConfig` enable-time prompts and a persistent plugin data dir are a planned fast-follow once a wider
> Claude Code baseline supports them; this release targets 2.1.109 and uses environment variables only.

## Scope limits

The hooks **fail open** (any uncertainty → silent pass), cover **user-scope agents only**
(`~/.claude/agents/`), and compliance is model-mediated. Full list in [CLAIMS.md](CLAIMS.md#scope-limits).

## License

[MIT](LICENSE).
