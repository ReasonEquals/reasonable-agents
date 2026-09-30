# Security

## No telemetry

**This release ships no network or telemetry code.** `reasonable-agents` v0.1 consists of plugin manifests,
shell hook scripts, and Markdown. The hook scripts read stdin, consult local files (for H6, possibly the
reviewing subagent's own transcript), and write to stderr, stdout (a JSON note), or local state — they make no
outbound network calls. Nothing about your usage is collected, transmitted, or
stored off your machine.

(Later releases are out of scope for this statement; each release re-states its own posture rather than making
a forward-looking absolute.)

## Kill switch

Enforcement is gated by environment variables read at the very top of each hook script. Export one in
your shell to disable enforcement; unset it (or set it to an off-value) to re-enable. The check is the
first thing each script does, so a disabled hook does no work — and the default is always **enforce**
(a variable that fails to propagate cannot silently turn enforcement off).

| Variable | Effect |
|---|---|
| `REASONABLE_AGENTS_DISABLE` | Master off-switch — set to `1`/`true`/`yes`/`on` to disable both hooks. |
| `REASONABLE_AGENTS_ENFORCE_PAIRING` | Set to `0`/`false`/`off` to disable H4 (pairing) only. Default on. |
| `REASONABLE_AGENTS_VALIDATE_REVIEWERS` | Set to `0`/`false`/`off` to disable H6 (output validation) only. Default on. |

## Fail-open posture

The hooks fail open by design: on any error or uncertainty they exit 0 (silent, or a non-blocking note). Their
own errors (a missing dependency, a parse failure, unwritable state) never block your work. Two cases can still
block, both capped by H6's per-session circuit breaker: a reviewer hand-back that delivered an empty report is
treated as a deficient review (deliberate), and drift in Claude Code's undocumented payload shape can make H6
misread a report (see the plugin-spec churn limit in [CLAIMS.md](CLAIMS.md#scope-limits)). This is a deliberate trust-ladder choice for code that runs on every
qualifying subagent call.

## Input handling & validator trust

The hooks treat their JSON stdin as untrusted. `subagent_type` and `session_id` are validated to the
`[a-z0-9-]` / `[A-Za-z0-9_-]` namespace **before** they are used in any file path, so a crafted value cannot
redirect the validator lookup or the circuit-breaker state file outside their intended directories. Pattern
matching uses `grep -E --` so a validator's `regex` can never be parsed as a grep option; the breaker never
follows a symlink and fails open if it cannot persist its own state.

When a reviewer hands its report back via `SubagentHandback` and the payload does not carry it, H6 reads the
subagent's own transcript, read-only, and only if `transcript_path` is absolute and ends in `.jsonl` and the
`agentId` is entirely `[a-z0-9]` (anything else is rejected, not stripped). A symlinked transcript *file* is
refused. That transcript is only as trustworthy as the subagent that writes it: a reviewer with shell access
could append a clean hand-back to its own transcript and suppress a block. The breaker's state file carries
the same bound, since that subagent could edit it too. H6 reduces malformed reviews; it is not a defense
against a hostile reviewer.

A **validator schema is executable-equivalent config**: H6 runs its `regex` with `grep` and injects its
`feedback_template` into your conversation. Install only validators you trust — treat a third-party
`<reviewer>.json` like any other code you would run.

## Supported surface

Local Claude Code CLI / desktop only. Web and cloud session behavior is unverified.

## Reporting

Found an issue? Please open a GitHub issue on the repository. There is no email channel — use issues so the
discussion is public and tracked.
