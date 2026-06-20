# Live pairing-compliance demo

The one claim the offline tests can't cover: that the model **complies** with H4's injected directive and
actually runs the reviewer. That the directive *fires* is mechanical (proved in `tests/h4.bats`); that the
model then *obeys* it is model-mediated — so it has to be measured live, and published as measured.

- **Date:** 2026-06-20
- **Model:** `claude-opus-4-8[1m]`
- **Pair:** the shipped fixture (`trail-route-planning-expert` / `-reviewer`) — the same pair in the README
  quickstart, so anyone can reproduce this.
- **n:** 10 fresh headless `claude -p` runs, clean throwaway profile.

## Method — neutral prompts (no priming)

Each run gave the orchestrator a **neutral** task — *"Use the trail-route-planning-expert subagent to plan a
\<N\>-day backpacking trip in \<area\>."* — with **no** instruction to run a reviewer. The point is to measure
*organic* compliance: after the expert runs and H4 injects its directive, does the model run the reviewer on
its own? Each hook was wrapped in a logger recording `{hook, subagent_type, rc}`; the side log is ground
truth (`claude -p --output-format stream-json` does not echo hook stderr).

## Results

| Run | Area | Expert ran (H4 fired) | Reviewer ran (complied) |
|---|---|---|---|
| 1 | Scottish Highlands | yes | yes |
| 2 | Patagonia | yes | yes |
| 3 | Sierra Nevada | yes | yes |
| 4 | Dolomites | — (no subagent invoked) | — |
| 5 | southern Appalachians | yes | yes |
| 6 | Tasmania | yes | yes |
| 7 | Pyrenees | yes | yes |
| 8 | Canadian Rockies | yes | yes |
| 9 | highland Iceland | yes | yes |
| 10 | Japanese Alps | yes | yes |

**Compliance: 9/9 — every run in which the expert ran ended with the reviewer run.** H4 fired on all 9 of
those runs, and the model complied with the directive on all 9.

## The one outlier, reported honestly

Run 4 invoked **no subagent at all** — its hook log is empty, so the expert never ran and H4 correctly had
nothing to pair. The cause is undetermined: either a transient session hiccup or the orchestrator answering
the trip directly without the expert. The throwaway transcript was not retained (born-dirty; see the
leak-safety note in `pack-dogfood/README.md`), so this account does not claim which. It is reported as a
no-subagent run, **not** counted as a compliance failure — and not re-rolled for a rounder number.

## Scope

Compliance is **model-mediated, not mechanical** — this is a measured rate on one pair on one day, not a
guarantee. It is the live half of the split in [CLAIMS.md](../CLAIMS.md): the directive *fires*
deterministically; the model *complies* at the rate measured here. Reconstructed from the side logs (parsed
`{hook, subagent_type, rc}` fields), never raw transcript.
