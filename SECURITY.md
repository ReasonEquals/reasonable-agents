# Security

## No telemetry

**This release ships no network or telemetry code.** `reasonable-agents` v0.1 consists of plugin manifests,
shell hook scripts, and Markdown. The hook scripts read stdin, consult local files, and write to stderr or
local state — they make no outbound network calls. Nothing about your usage is collected, transmitted, or
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

The hooks fail open by design: on any error or uncertainty they exit 0 (silent pass). They never block your
work because of their own malfunction. This is a deliberate trust-ladder choice for code that runs on every
qualifying subagent call.

## Input handling & validator trust

The hooks treat their JSON stdin as untrusted. `subagent_type` and `session_id` are validated to the
`[a-z0-9-]` / `[A-Za-z0-9_-]` namespace **before** they are used in any file path, so a crafted value cannot
redirect the validator lookup or the circuit-breaker state file outside their intended directories. Pattern
matching uses `grep -E --` so a validator's `regex` can never be parsed as a grep option; the breaker never
follows a symlink and fails open if it cannot persist its own state.

A **validator schema is executable-equivalent config**: H6 runs its `regex` with `grep` and injects its
`feedback_template` into your conversation. Install only validators you trust — treat a third-party
`<reviewer>.json` like any other code you would run.

## Supported surface

Local Claude Code CLI / desktop only. Web and cloud session behavior is unverified.

## Reporting

Found an issue? Please open a GitHub issue on the repository. There is no email channel — use issues so the
discussion is public and tracked.
