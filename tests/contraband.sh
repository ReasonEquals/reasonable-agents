#!/usr/bin/env bash
# reasonable-agents — contraband gate (permanent: CI job + local pre-commit check).
#
# Greps every shipped file for tokens that must NEVER appear in this public
# package: author identity, private knowledge-base paths, health data, client and
# methodology terms, and raw email addresses. Exits non-zero on any hit.
#
# This file ships in tests/ on purpose — the blocklist is itself a receipt — so it
# necessarily contains every pattern and therefore EXCLUDES ITSELF from the scan.
#
# Design notes / limits:
#   * Scans the working tree only. It does NOT read .git/ history; commit metadata
#     is guarded separately (pinned commit identity + a `git log` author check). In a
#     git worktree, `.git` is a FILE (a `gitdir:` pointer holding an absolute path),
#     not a directory, so it is excluded by name as well as by --exclude-dir.
#   * Tokens are matched as case-insensitive SUBSTRINGS (no word boundaries). A
#     leak gate must err toward over-catching: word boundaries were considered and
#     rejected because they create false NEGATIVES on "_"-joined identifiers and
#     because "\b" is not portable across BSD (macOS) and GNU (CI) grep. A rare
#     false positive is fixed with a targeted exception; a missed leak is not
#     acceptable.
#   * `reasonequals` is intentionally NOT a token: it is the public publishing org
#     and appears legitimately in the manifests, README, and LICENSE.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Private identity | knowledge-base paths | health | client + methodology | raw emails.
PATTERN='ryan|walsh|juno|concord|spinal|qrspi|horthy|reasons_brain|reason-cowork|reasons-os|persona-evals|os\.db|/Users/|adhd|adderall|whoop|discord.*token|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]'

# Scan binaries as text (-a, not -I): a leak gate must never skip a file just because it
# contains a NUL byte. This gate's own source necessarily contains the blocklist, so it is
# self-excluded by EXACT path (not by basename) — a stray file named contraband.sh
# elsewhere cannot evade the scan.
self="${ROOT}/tests/contraband.sh"
set +e
matches="$(grep -raniE "${PATTERN}" "${ROOT}" \
  --exclude-dir=.git \
  --exclude-dir=.claude \
  --exclude-dir=node_modules \
  --exclude='.git' 2>/dev/null)"
rc=$?
set -e

# grep rc: 0 = matches, 1 = no matches, >1 = real error.
if [ "${rc}" -gt 1 ]; then
  printf 'contraband: ERROR — grep failed (rc=%s); not certifying clean.\n' "${rc}" >&2
  exit 2
fi

# Drop lines from this gate's own source (matched at line-start by exact path; literal).
matches="$(printf '%s\n' "${matches}" | awk -v s="${self}:" 'NF && index($0, s) != 1')"

if [ -n "${matches}" ]; then
  printf '%s\n' "${matches}" >&2
  printf '\nCONTRABAND: private token(s) found in shipped files (see matches above).\n' >&2
  exit 1
fi

printf 'contraband: clean — no private tokens in shipped files.\n'
exit 0
