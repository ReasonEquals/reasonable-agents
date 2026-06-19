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

rc=0
grep -rInE "${PATTERN}" "${ROOT}" \
  --exclude-dir=.git \
  --exclude-dir=.claude \
  --exclude-dir=node_modules \
  --exclude='.git' \
  --exclude='contraband.sh' || rc=$?

case "${rc}" in
  0)
    printf '\nCONTRABAND: private token(s) found in shipped files (see matches above).\n' >&2
    exit 1
    ;;
  1)
    printf 'contraband: clean — no private tokens in shipped files.\n'
    exit 0
    ;;
  *)
    printf 'contraband: ERROR — grep failed (rc=%s); not certifying clean.\n' "${rc}" >&2
    exit 2
    ;;
esac
