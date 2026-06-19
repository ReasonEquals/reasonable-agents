#!/usr/bin/env bash
# reasonable-agents — reviewer-output structural validator (PostToolUse / Agent).
#
# PHASE-1 PLACEHOLDER — fail-open no-op.
# Ships so hooks.json resolves to a real path and the plugin installs cleanly. The
# real logic (validate a reviewer subagent's output against a structural schema and
# inject a re-invoke directive on failure) is ported in the next release. Current
# behavior: discard stdin and exit 0 (silent pass). No environment variables are
# read yet — this is NOT live enforcement.
set -u
cat >/dev/null 2>&1 || true
exit 0
