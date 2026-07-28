# ADR-0035: Input Fidelity for Delegated Briefs

## Context and Problem Statement

Brief-building delegator skills compose custom input for fresh-context workers. If the delegator summarizes, truncates, or selectively rewrites the user's original request, the worker can lose requirements before it ever reasons about the task. This is especially risky for dual-engine and executor flows where the worker's independence depends on neutral, complete input.

## Considered Options

- Document the convention only.
- Validate full prompt diffs mechanically.
- Require a curated lint marker plus an enrichment-only prose contract.

## Decision Outcome

Chosen option: **Require a curated lint marker plus an enrichment-only prose contract** — it gives a hard structural check for known delegators while leaving the semantic brief construction in skill prose.

## Consequences

- Good: delegated workers receive the original prompt/request verbatim and in full, plus enriching context, interview Q&A, raw code excerpts, and constraints.
- Good: the coordinator's own verdict or proposed solution remains the single deliberate omission, preserving bias isolation for independent workers.
- Good: `cog skill-lint` catches missing declarations in the curated brief-building delegator set.
- Bad: marker presence does not prove the prose or runtime behavior is semantically faithful.
- Bad: the curated delegator set must be maintained when new brief-building delegators are added.

## Status

Superseded by [ADR-0043](./0043-best-constructed-input-standard.md) — the verbatim-and-in-full mandate is replaced by the best-constructed input standard (oriented summary + raw request attached + full substantive context and artifacts, unbiased). The `input-fidelity` marker and lint rule are retained with redefined meaning.
