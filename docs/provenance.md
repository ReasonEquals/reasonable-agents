# Provenance — why H6 validates reviewer output

The reviewer-output validator (H6) exists because **prompt-level enforcement of a reviewer's
structural protocol was measured to be insufficient.**

In a documented evaluation of an adversarial-reviewer persona, the persona's own system prompt
instructed it to always begin its response with a fixed set of structural tables — a
verification-questions walk, a kill-case enumeration, and a contrarian-take check — before addressing
the caller's request. Across three separate runs, the reviewer **did not** produce those tables when
the caller's prompt supplied its own competing structure: the caller-prompt structure overrode the
agent's standing instruction. The required elements were dropped exactly when they mattered most.

The lesson: an instruction that lives only inside the agent's system prompt is not load-bearing
against a strong caller prompt. To make the structure stick, enforcement has to live **outside** the
agent — at the harness layer, after the agent runs. That is what H6 does: it reads the reviewer's
output, checks it against a small structural schema (named regex patterns), and, on a miss, injects a
re-invoke directive whose preamble re-asserts the required structure with priority over the caller's.
A per-session circuit-breaker caps how many times it will do this.

This is also why the package leads with **enforcement** rather than verification: the validator is the
support act; the load-bearing idea is that the check runs at a layer the agent prompt cannot talk its
way around. The honest scope limit still applies — H6 fails open, and compliance with the re-invoke
directive is model-mediated, not mechanical (see [CLAIMS.md](../CLAIMS.md)).

*This page is a sanitized account of the original finding. It ships no private paths, identifiers, or
evaluation data — only the mechanism and the lesson.*
