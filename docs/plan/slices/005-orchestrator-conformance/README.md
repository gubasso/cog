# 005 — Orchestrator conformance

<!-- markdownlint-configure-file { "MD043": { "headings": ["# 005 — Orchestrator conformance","## Goal","## Appetite","## Core","## In scope","## Out of scope","## Governed by","## Acceptance","## Rabbit holes","## Done when","## Revisions"] } } -->

## Goal

A shell, JSON, and exit-code fixture reaches one golden workflow result without vendor assumptions.

## Appetite

2 implementation sessions. Chosen before the design below.

## Core

One vendor-neutral fixture proves capability negotiation and terminal behavior, leaving broader provider coverage as remainder.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Cover parallel and sync behavior, loop exhaustion, pause and resume, stale tokens, and crash recovery. A candidate driver is conformant exactly when it drives the fixture to the golden.
- Carry the proposed capability negotiation: an orchestrator declares `name`, `version`, and `capabilities` once at `resolve`, and cog enforces rather than trusts. Absent `parallel`, `next` returns at most one dispatch directive; absent `inline`, a `context: inherit` step fails closed; absent `ask-user`, a `requires_judgment` directive becomes a hard failure; absent `subprocess`, only `context: inherit` steps are dispatchable.
- Carry the proposed driver obligations. It must run a shell command and read stdout and the exit code, parse JSON, declare itself once, drive `next` to `claim` to dispatch to `record` while the run is active and re-issue on `75`, dispatch by any means it has, pass the claim token on `record` and the decision token on `advance`, honor `sync` and the declared input and output contract, reconcile every durable `running` claim after a restart, surface `requires_judgment` to a human or abort, and stop on a terminal state. It must not edit `state.json` or `workflow.json`, write any `outputs.json`, synthesize ids, handles, or counters, infer a round count, re-dispatch a `running` node without `reclaim`, reimplement the expression language, or treat any terminal state but `done` as success. Subagents, a depth budget, parallelism, streaming, a tool-call protocol, plan mode, and MCP are explicitly not required.
- Make depth an opt-in `max-fresh-depth` contract rather than a vendor base number.
- Publish workflow and orchestrator reference pages under the accepted ADR. Reference prose is cut before fixture coverage.

## Out of scope

- Provider authentication, model policy, and production orchestration migration.
- Performance benchmarking or autonomous scheduling.

## Governed by

- `docs/plan/slices/004-composites-loops-and-recovery/README.md` — runtime state contract.
- `docs/decisions/0009-orchestration-and-durable-jobs.md` — orchestration boundary.
- `docs/reference/orchestration-contract.md` — current runner and claim semantics.
- `docs/decisions/0003-machine-facing-output-contract.md` — JSON and exit behavior.

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

None.
