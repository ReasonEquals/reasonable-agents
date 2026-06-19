# Security

## No telemetry

**This release ships no network or telemetry code.** `reasonable-agents` v0.1 consists of plugin manifests,
shell hook scripts, and Markdown. The hook scripts read stdin, consult local files, and write to stderr or
local state — they make no outbound network calls. Nothing about your usage is collected, transmitted, or
stored off your machine.

(Later releases are out of scope for this statement; each release re-states its own posture rather than making
a forward-looking absolute.)

## Kill switch

Enforcement is gated by environment variables read at the top of each hook script (for example,
`REASONABLE_AGENTS_DISABLE=1`). Export the variable in your shell to disable enforcement; unset it to
re-enable. The check is the first thing each script does, so a disabled hook does no work.

*(In v0.1 the hooks are no-op placeholders, so these switches are reserved until enforcement lands.)*

## Fail-open posture

The hooks fail open by design: on any error or uncertainty they exit 0 (silent pass). They never block your
work because of their own malfunction. This is a deliberate trust-ladder choice for code that runs on every
qualifying subagent call.

## Supported surface

Local Claude Code CLI / desktop only. Web and cloud session behavior is unverified.

## Reporting

Found an issue? Please open a GitHub issue on the repository. There is no email channel — use issues so the
discussion is public and tracked.
