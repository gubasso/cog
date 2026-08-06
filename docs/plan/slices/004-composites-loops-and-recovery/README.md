# 004 — Composites, loops, and recovery

<!-- markdownlint-configure-file { "MD043": { "headings": ["# 004 — Composites, loops, and recovery","## Goal","## Appetite","## Core","## In scope","## Out of scope","## Governed by","## Acceptance","## Rabbit holes","## Done when","## Revisions"] } } -->

## Goal

Composite calls and one loop execute without double dispatch and recover after a driver restart.

## Appetite

3 implementation sessions. Chosen before the design below.

## Core

One composite and one lazily materialized loop survive restart with a single writer for every state artifact; retries and scheduling remain negotiable exclusions.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Add expressions, re-exports, lazy round materialization, stable instance ids, terminal states, and run locking. Templates and instances stay separate top-level maps in `state.json` so rounds grow without the graph growing.
- Carry the four run-state fields that do work beyond their size: `inputs_frozen`, materialized once at loop entry and never re-read, so a round cannot pick up a changed value; `rounds[].scalars`, retaining each round's `until` evaluation and the values behind it; `dispatch`, an opaque orchestrator-supplied blob cog stores and hands back without interpreting, which is what keeps the contract vendor-neutral across a crash; and `workflow_digest`, rechecked on every call and failing closed on mismatch.
- Carry the crash semantics: an absent receipt means the node never terminated, so `next` reports the instance `running` with its `lease_age` and the orchestrator reclaims. A malformed receipt is cog's own emitter failing, so it exits `1` rather than `2`.
- Enforce definition-owned `sync` through claim scope without inventing a TTL.
- Keep agent `scalars.json` and cog `outputs.json` under one writer each; composites emit no stdout, leaves alone emit stdout.
- Add stale-token, exhausted-loop, crash, reclaim, and resolve-time composite-output tests. These tests are cut last.

## Out of scope

- Retries, backoff, autonomous scheduling, and distributed locking.
- A second loop form or arbitrary expression language.

## Governed by

- `docs/plan/slices/002-workflow-engine-go-no-go/README.md` — accepted grammar.
- `docs/plan/slices/003-linear-workflow-vertical/README.md` — receipt and lifecycle foundation.
- `docs/decisions/0009-orchestration-and-durable-jobs.md` — durable recovery constraints.
- `docs/reference/orchestration-contract.md` — claim and runner boundary.

## Acceptance

```text
When a composite loop restarts, the workflow system shall reclaim eligible work without double dispatch. -> test/integration/cmd_workflow_recovery.bats
If a composite attempts leaf stdout or a stale token records output, then the workflow system shall fail deterministically. -> test/integration/cmd_workflow_recovery.bats
```

## Rabbit holes

- Expression evaluation can become a programming language — escape: retain only the accepted input and step-output paths.
- Recovery can invite time-based ownership — escape: use explicit claim and reclaim writers with no TTL.

## Done when

Composite, loop exhaustion, token, locking, crash, and reclaim cases pass in the named integration file and milestone 004 flips to `done`.

## Revisions

None.
