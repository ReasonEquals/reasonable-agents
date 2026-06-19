#!/usr/bin/env bash
# reasonable-agents — adversarial-pairing enforcement hook (PostToolUse / Agent).
#
# PHASE-1 PLACEHOLDER — fail-open no-op.
# Ships so hooks.json resolves to a real path and the plugin installs cleanly. The
# real logic (block the turn when an *-expert subagent ran without its paired
# *-reviewer) is ported in the next release. Current behavior: discard stdin and
# exit 0 (silent pass). No environment variables are read yet — this is NOT live
# enforcement.
set -u
cat >/dev/null 2>&1 || true
exit 0
