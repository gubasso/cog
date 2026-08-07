# 004 — Composites, loops, and recovery

## Goal

Composite calls and one loop execute without double dispatch and recover after a driver restart.

## Appetite

3 implementation sessions. Chosen before the design below.

## Core

One composite and one lazily materialized loop survive restart with a single writer for every state artifact; retries and scheduling remain negotiable exclusions.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Add re-exports, lazy round materialization, stable instance ids, terminal states, and run locking. Templates and instances stay separate top-level maps in `state.json` so rounds grow without the graph growing.
- Carry the four run-state fields that do work beyond their size: `inputs_frozen`, materialized once at loop entry and never re-read, so a round cannot pick up a changed value; `rounds[].decision`, retaining each round's outcome, reason, and note so a convergence call stays auditable after the fact; `dispatch`, an opaque orchestrator-supplied blob cog stores and hands back without interpreting, which is what keeps the contract vendor-neutral across a crash; and `workflow_digest`, rechecked on every call and failing closed on mismatch.
- Carry the crash semantics: an absent receipt means the node never terminated, so `next` reports the instance `running` with its `lease_age` and the orchestrator reclaims. A malformed receipt is cog's own emitter failing, so it exits `1` rather than `2`.
- Keep every state artifact under one writer: the agent owns its own step directory, cog owns `outputs.json` and `state.json`. A composite runs no agent and produces no directory of its own beyond what its children wrote.
- Add stale-token, exhausted-loop, incomplete-round, crash, reclaim, and resolve-time composite-output tests. These tests are cut last.

## Out of scope

- Retries, backoff, autonomous scheduling, and distributed locking.
- A second loop form or arbitrary expression language.

## Governed by

- `docs/reference/workflow-contract.md` — accepted grammar and loop rules.
- `docs/decisions/ADR-0026-judge-loop-convergence-with-a-prose-criterion.md` — who judges convergence and what cog still enforces.
- `docs/plan/slices/003-linear-workflow-vertical/README.md` — receipt and lifecycle foundation.
- `docs/decisions/ADR-0009-orchestration-and-durable-jobs.md` — durable recovery constraints.
- `docs/reference/orchestration-contract.md` — claim and runner boundary.

## Acceptance

```text
When a composite loop restarts, the workflow system shall reclaim eligible work without double dispatch. -> test/integration/cmd_workflow_recovery.bats
If a stale token records output or a round that produced no files reports convergence, then the workflow system shall fail deterministically. -> test/integration/cmd_workflow_recovery.bats
```

## Rabbit holes

- A judged convergence call can be trusted without evidence — escape: refuse `continue` and `converged` on a round that produced no files, and record every decision with its reason.
- Recovery can invite time-based ownership — escape: use explicit claim and reclaim writers with no TTL.

## Done when

Composite, loop exhaustion, token, run locking, crash, and reclaim cases pass in the named integration file and milestone 004 flips to `done`.

## Revisions

None.
