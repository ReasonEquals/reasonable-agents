# Pack dogfood receipts

Each `<triple>.md` here is a receipt that the corresponding starter-pack triple was **built and validated
through the plugin's own enforcement chain**, live, before shipping. The Phase 3 gate requires every shipped
triple to pass its dogfood enforcement run.

## What was proven, per triple

A clean headless `claude -p` session was asked to use the `<triple>-expert` subagent on a generic,
public-domain design task. With the plugin's hooks active:

1. the expert ran, and **H4** injected the pairing directive (`rc=2`);
2. the orchestrator ran the paired `<triple>-reviewer`;
3. **H6** validated the reviewer's natural output against `validators/<triple>-reviewer.json` and passed
   (`rc=0`) — i.e. each reviewer's own output satisfies its own schema on the first try, the hardest
   correctness property of a triple.

## Method (the live-testing constraints this works around)

- A fully isolated `$HOME` breaks `claude -p` auth (credentials are HOME-bound), so the real home is used and
  the user's own hooks co-fire on the same event.
- `claude -p --output-format stream-json` does **not** echo hook stderr, so you cannot confirm a hook fired by
  reading the stream.

So each hook was registered (via `--settings`) behind a **logger wrapper** that runs the real hook with the
real payload, records `{hook, subagent_type, rc}` to a side log, and re-emits the hook's stderr + exit code
unchanged (behaviour identical to running the hook directly). **The side log is the ground truth** quoted in
each receipt. The personas were copied into `~/.claude/agents/` so the subagents were invocable and so H4's
`~/.claude/agents/<reviewer>.md` lookup resolved; a trap removed them and the throwaway project afterward.

## Leak-safety

The throwaway transcripts and side logs are born-dirty (they contain home paths). They are **not** committed.
Each receipt is constructed from parsed fields (`hook`, `subagent_type`, `rc`) plus a reviewer-output excerpt
that was scanned against the contraband pattern set; `tests/contraband.sh` is the hard gate over this whole
directory before commit.

This is not hypothetical: in one run the `security-threat-modeling` reviewer (which has the `Bash` tool, as
reviewers do) ran a directory listing while reviewing, pulling the host's OS account name into its raw output.
The contraband gate flagged it, and because each receipt quotes only the vetted structural skeleton (header
rows + the verdict line) and never the raw transcript, nothing leaked into a committed file — the leak-safety
design working exactly as intended.

## Reproduce

Copy a triple's expert + reviewer into `~/.claude/agents/`, ensure the plugin is installed (so H6 finds the
shipped validator via `${CLAUDE_PLUGIN_ROOT}`), and ask Claude to use the `<triple>-expert` on a task. Watch
H4 fire, let the reviewer run, and watch H6 pass. The offline equivalent (no API spend) is `tests/pack.bats`.
