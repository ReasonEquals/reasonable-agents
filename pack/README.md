# reasonable-agents — starter persona pack

Six ready-to-use **expert + reviewer + validator** triples you can drop into your own setup. Each pair is
governed by the plugin's enforcement hooks: after the `*-expert` runs, **H4** reminds you to run the paired
`*-reviewer`; after the reviewer runs, **H6** checks its output against the matching schema in `validators/`.

These personas are **born-clean and generic** — authored fresh from public domain knowledge, not extracted
from anyone's private config. They start **advisory**: the hooks fail open, nothing auto-executes, and the
reviewers only read files and run shell verification commands. Treat each as a starting point and edit freely.

## The triples

| Expert | Reviewer | What the reviewer catches |
|---|---|---|
| `software-architecture-review-expert` | `software-architecture-review-reviewer` | failure modes & hidden coupling in an architecture proposal |
| `agent-and-prompt-design-expert` | `agent-and-prompt-design-reviewer` | prompt-injection surface, scope ambiguity, missing eval coverage |
| `api-contract-design-expert` | `api-contract-design-reviewer` | backward-incompatible changes & unspecified contract facets |
| `security-threat-modeling-expert` | `security-threat-modeling-reviewer` | missed threats & uncontrolled trust boundaries (STRIDE) |
| `test-strategy-design-expert` | `test-strategy-design-reviewer` | coverage gaps & brittle / flaky test design |
| `boss-fight-design-expert` | `boss-fight-design-reviewer` | unfair balance & degenerate exploits (a deliberately fun one) |

## Install

Copy the expert + reviewer of any triple into your user agents dir:

```bash
mkdir -p ~/.claude/agents
cp pack/software-architecture-review-expert.md   ~/.claude/agents/
cp pack/software-architecture-review-reviewer.md ~/.claude/agents/
```

The matching validator schema already ships in `validators/`. When the plugin is installed, **H6 finds it
automatically** via the `${CLAUDE_PLUGIN_ROOT}/validators/<reviewer>.json` fallback — you do not copy it
anywhere. (If you ever run the hooks without the plugin root set, copy the schema to
`~/.claude/state/reasonable-agents/validators/` instead, where H6 also looks.)

Then, in Claude Code, ask Claude to use `software-architecture-review-expert` on a design task. When it
finishes, **H4** tells Claude to run `software-architecture-review-reviewer`; when the reviewer finishes,
**H6** checks its output (a Concern table, a Failure-mode table, and a `VERDICT:` line) and re-invokes it if
a required element is missing.

## The binding rule (if you fork or rename)

For a triple to work, three names must be identical: the reviewer's frontmatter `name`, its filename stem,
and its validator filename stem. H4 derives the reviewer name by replacing the expert's `-expert` suffix with
`-reviewer`; H6 looks up `validators/<reviewer-name>.json`. Keep all three in lockstep (`[a-z0-9-]` only) or
enforcement silently no-ops (the hooks fail open by design).

## A note for maintainers

Several reviewers use **domain-flavored verdict vocabularies on purpose** — `api-contract-design`
(`COMPATIBLE` / `REVISE` / `BREAKING`), `security-threat-modeling` (`PASS` / `HARDEN` / `BLOCK`),
`boss-fight-design` (`SHIP` / `TUNE` / `REWORK`). These are not typos. Do not "normalize" them to a single
vocabulary: each validator's verdict pattern is hand-matched to its own reviewer's wording, and that
hand-matching is part of what the pack demonstrates. For the same reason the api compatibility table matches
the keyword `Change` (not `Breaking`), because "Breaking" / "Non-breaking" routinely appear in that table's
other cells and would otherwise satisfy the check vacuously.
