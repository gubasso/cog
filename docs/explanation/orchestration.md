# Orchestration

Cog uses same-context chaining until a true isolation boundary requires a fresh worker. [ADR-0009](../decisions/0009-orchestration-and-durable-jobs.md), [ADR-0016](../decisions/0016-context-briefs-and-input-fidelity.md), and [ADR-0022](../decisions/0022-forge-resistant-approval.md) own the governing choices.

## Components and boundaries

Coordinators sequence work in prose. Foreground delegation isolates judgment or context, bounded by the fixed five-level depth budget. Long Codex work uses cog-owned durable jobs with explicit state, output, events, and stderr artifacts.

Context briefs carry an oriented objective, raw request, and full substantive context while omitting the coordinator's solution. Approval records bind an operator decision to the exact artifact hash and expiry.

## Current constraints

Environment guarantees are checked before orchestration, Codex is never backgrounded by skill prose, and every boundary verifies a durable postcondition. The exact contract lives in [orchestration reference](../reference/orchestration-contract.md).

## Unresolved

- Provider-specific runtime limits remain external facts and must be revalidated when used.
