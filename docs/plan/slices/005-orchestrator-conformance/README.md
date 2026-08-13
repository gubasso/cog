# 005 — Orchestrator conformance

## Goal

A shell, JSON, and exit-code fixture reaches one golden workflow result without vendor assumptions.

## Appetite

2 implementation sessions. Chosen before the design below.

## Core

One vendor-neutral fixture proves capability negotiation and terminal behavior, leaving broader provider coverage as remainder.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Cover parallel and ordering behavior, loop exhaustion, pause and resume, stale tokens, and crash recovery. A candidate driver is conformant exactly when it drives the fixture to the golden. The fixture scripts its driver's loop outcomes, because a real convergence judgment is not deterministic and a golden cannot assert one.
- Carry the proposed capability negotiation: an orchestrator declares `name`, `version`, and `capabilities` once at `resolve`, and cog enforces rather than trusts. Absent `parallel`, `next` returns at most one dispatch directive; absent `inline`, a `context: inherit` step fails closed; absent `ask-user`, a `requires_judgment` directive becomes a hard failure; absent `subprocess`, only `context: inherit` steps are dispatchable.
- Carry the proposed driver obligations. It must run a shell command and read stdout and the exit code, parse JSON, declare itself once, drive `next` to `claim` to dispatch to `record` while the run is active and re-issue on `75`, dispatch by any means it has, pass the claim token on `record` and the decision token on `advance`, hand each step the upstream directories cog names for it, read a loop's `until:` criterion and report its own judgment on `advance`, reconcile every durable `running` claim after a restart, surface `requires_judgment` to a human or abort, and stop on a terminal state. It must not edit `state.json` or `workflow.json`, write any `outputs.json`, synthesize ids, handles, or counters, infer a round count, re-dispatch a `running` node without `reclaim`, or treat any terminal state but `done` as success. Subagents, a depth budget, parallelism, streaming, a tool-call protocol, plan mode, and MCP are explicitly not required.
- Make depth an opt-in `max-fresh-depth` contract rather than a vendor base number.
- Publish the orchestrator reference page under the accepted ADR; the workflow contract already has its own owner. Reference prose is cut before fixture coverage.

## Out of scope

- Provider authentication, model policy, and production orchestration migration.
- Performance benchmarking or autonomous scheduling.

## Governed by

- `docs/plan/slices/004-composites-loops-and-recovery/README.md` — runtime state contract.
- `docs/decisions/ADR-0009-orchestration-and-durable-jobs.md` — orchestration boundary.
- `docs/reference/orchestration-contract.md` — current runner and claim semantics.
- `docs/decisions/ADR-0003-machine-facing-output-contract.md` — JSON and exit behavior.

## Acceptance

```text
When the conformance fixture runs, the orchestrator shall reach the golden shell, JSON, and exit-code result. -> test/integration/cmd_workflow_conformance.bats
If pause, stale token, or crash recovery occurs, then the fixture shall preserve one deterministic terminal history. -> test/integration/cmd_workflow_conformance.bats
```

## Rabbit holes

- Vendor details can leak into the fixture — escape: model providers as negotiated capabilities only.
- Golden files can hide semantic omissions — escape: assert state transitions as well as final bytes.

## Done when

The vendor-neutral fixture passes every named branch unskipped and milestone 005 flips to `done`.

## Revisions

Prose ahead of fixture: the four specification bullets — capability negotiation, the driver obligations, `max-fresh-depth` as an opt-in contract, and the reference page — landed as `docs/reference/orchestrator-contract.md` while the workflow engine is under a code freeze, so the conformance fixture named in `Acceptance` is unwritten. What changed the order is that slice 006 is governed by this contract and needs it fixed, and a contract can be written from two real implementations plus the accepted grammar, while a fixture cannot be written against a runtime that slice 004 has not built. The slice stays `shaped` rather than moving to `active`: the fixture is its `Core` and is unstarted, and the milestone surface defines `active` as the status whose acceptance targets exist. Nothing was cut.

Two gaps in the capability bullet, settled rather than written past. First, it enforces `inline` and `subprocess` against a `context: inherit` step, but the grammar had no per-node `context:` key and ADR-0023 called the workspace selector inert; ADR-0030 promotes `context:` to an optional key on a node, because two of the four capabilities have nothing to range over otherwise and a definition that mixes an in-session judgment with a forked worker is the shape slice 007 expects. Second, it makes `requires_judgment` a directive an orchestrator must surface, but nothing emitted or defined it; the reference page defines it as a directive cog emits, raised today only by a loop's `until:` criterion reaching `advance` as the existing `needs-user` reason. Both are marked on that page as specified and not yet implemented.
