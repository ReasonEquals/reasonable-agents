# reasonable-agents

Most agent-persona packs ship a reviewer as a markdown file and hope the agent reads it. The hope is the bug.
An agent that just produced 400 lines of confident work is the worst judge of whether that work is any good,
and a review instruction sitting in a sibling file does nothing if the turn ends before anyone runs it.

`reasonable-agents` is a Claude Code plugin that moves the review out of the agent's good intentions and into
the harness. Two hooks do it:

- **H4, pairing.** After an `*-expert` subagent runs, if its paired `*-reviewer` exists and hasn't run this
  session, H4 injects a directive to run it before the turn proceeds.
- **H6, output validation.** After a reviewer runs, H6 checks its output against a per-persona schema: the
  required tables plus a verdict keyword. Miss one and it injects a re-invoke directive that names the
  specific thing missing, capped by a per-session circuit breaker.

Both fail open. Missing schema, empty output, a parse error, a missing dependency: exit 0, stay out of the
way. And the one line of honesty the whole project is built on. Compliance with an injected directive is
model-mediated, not mechanical. The hook makes the review fire. It can't make the model obey. So the package
publishes a measured compliance rate instead of calling the review "forced."

## Receipts, not adjectives

Every claim names a check you can run.

| Claim | Receipt |
|---|---|
| An `*-expert` without its reviewer triggers a blocking directive | `tests/h4.bats`: offline payload replay |
| Malformed reviewer output triggers a re-invoke that names the *specific* missing element | `tests/h6.bats`: the strengthened negative test |
| The directive fires whenever the expert runs; the model then complies at a measured rate | `bench/live-pairing-demo.md`: 10 neutral runs. The expert ran in 9; H4 fired in all 9; the model ran the reviewer in all 9 (9/9). One run invoked no subagent |
| Each shipped starter persona's reviewer passes its own schema, run for real | `bench/pack-dogfood/*.md`: 6 triples, dogfooded end to end |
| Harness enforcement exists because prompt-level enforcement measurably failed | `docs/provenance.md` |
| No personal data ships | `tests/contraband.sh`: a CI gate, run on every commit |

The split in the middle two rows is the honest core. That the directive fires is mechanically provable and
runs offline, no API spend. That the model then complies is a live number. Measured, published as-is, not
rounded up to "guaranteed."

## The skeptic caught my own bugs, three times

Not a thought experiment. The review earned its keep on the plugin's own construction.

1. **Bare-string dedup (H4).** The first dedup matched the reviewer's name as a quoted string anywhere in the
   transcript. A reviewer merely mentioned in prose would have counted as "already run," silently suppressing
   the directive. Fixed to match the structured `subagent_type` field. A mention no longer counts as a run.
2. **Kill-switch `:-` cascade.** An early kill-switch used a positional `:-` default that could read as "off"
   on an empty value. Enforcement silently disabled by a propagation glitch. Fixed to normalize and
   explicit-set-match, default-enforce.
3. **A vacuous schema, caught before it shipped.** Planning the starter pack, the reviewer flagged that
   keying the API reviewer's compatibility table on the word `Breaking` would pass vacuously. "Breaking" and
   "Non-breaking" show up in the cells of the next table over, so a reviewer could drop the real compatibility
   table and still slip through. The schema keys on `Change` now, and a test proves a
   Facet-table-with-Breaking-cells-but-no-Change-table still blocks.

None of these got caught by writing the code. All three got caught by running the skeptic against the plan.
That is the product, run on itself.

## The starter pack, built through the harness it installs

An empty harness can't be fairly evaluated. So the plugin ships six born-clean expert + reviewer + validator
triples in `pack/`: `software-architecture-review`, `agent-and-prompt-design`, `api-contract-design`,
`security-threat-modeling`, `test-strategy-design`, and `boss-fight-design`. Authored fresh from public domain
knowledge, not scrubbed from anyone's config.

Each one was dogfooded through the plugin's own chain before shipping. A clean headless session runs the
expert on a generic task, H4 fires, the reviewer runs, and H6 validates the reviewer's natural output against
its own schema. It passed first try, every time. The runs are in `bench/pack-dogfood/`.

Proving that meant working around three live-testing facts: HOME-bound auth, the user's own hooks co-firing on
the same event, and stream-json swallowing hook stderr. The fix is a logger wrapper whose side log is the
ground truth. That wrapper then caught a real leak in the act. A `Bash`-enabled reviewer ran `ls` mid-review
and pulled the host account name into its output. The contraband gate flagged it. Receipts are rebuilt from
parsed fields and never quote the raw transcript, so nothing reached a committed file. The leak-safety design,
shown surviving a real leak.

## What "validated" means, and what it doesn't

Validated here means process-validated: briefing-grounded, adversarially paired, schema-checked. It is not a
domain-accuracy benchmark, and not a guarantee the expert is right. The hooks reduce missed reviews. They are
not a hard gate. Reviewer lookup is user-scope only (`~/.claude/agents/`), dedup is best-effort across
sessions, and behavior is verified on the local CLI and desktop. All of it is written down in
[CLAIMS.md](../CLAIMS.md) and [SECURITY.md](../SECURITY.md). On a tool whose whole pitch is trustworthy
review, the honesty discipline is the credibility.

## A sibling application

The expert-and-skeptic pair is what's new in reasonable-agents. A domain expert and its adversarial
reviewer, blocked at the hook layer until the skeptic has run and its output passes a schema. Everything
above is about that.

What generalizes is one layer down. The pair is a payload. The spine underneath is the point: enforcement
in the harness, not in prose the model can talk its way around. Swap the payload and the spine still holds.

The clearest proof is a second plugin already running on that spine. It carries Dexter Horthy's QRSPI
methodology instead of an expert and a reviewer. The hooks are the same shape; what they guard is different.
A dumb-zone block that stops further edits once context degrades. A research step that hides the ticket from
the researcher, so the answers come back as facts instead of opinions about what to build. A session-review
gate that holds a commit suggestion until the review has run. Different guardrails, same move: the check sits
where the model can't argue with it.

It's written up separately, and it points back here for the technique instead of absorbing it. Same play,
two angles, each billed on its own.

<!-- TODO: link the QRSPI writeup once it has a public home -->

## What's next

This release is the enforcement chain, the starter pack, and these receipts. Minting triads on demand, the
eval scaffolds, and the broader persona library are later phases, gated on whether this one earns real use.
The thing worth copying isn't the persona files. It's the pattern. Put the check at a layer the agent can't
talk its way around, then measure and publish how well it holds.
