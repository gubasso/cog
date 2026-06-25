# ADR-0028: Executor stage-phase decoupling

## Context and Problem Statement

`cog executor` originally encoded one reviewed 3-stage flow directly into its command and helper
contracts: `stage1` meant plan, `stage2` meant reviewed plan, and `stage3` meant execution. That
worked for `executor-vetted`, but it could not represent a 2-stage executor where `stage2` is
execution.

The same command surface also used `--executor claude|codex-session` to mean the coding agent. That
conflicted with the skill taxonomy, where an `executor-*` name is the routine that executes one
prompt or plan.

## Decision Outcome

Chosen option: **per-executor flow descriptors with explicit executor and engine identity**.

`cog executor` now treats:

- `--executor <executor-vetted|executor-oneshot>` as the executor skill/routine that selects the flow.
- `--engine <claude|codex>` as the coding agent that plans and implements.

The removed `--plan-engine` flag is redundant because the plan engine is the selected engine.

Executor flows are declared in `cog::fn::executor::flow_json`:

- `executor-vetted`: reviewed 3-phase flow, plan -> review -> execution.
- `executor-oneshot`: unreviewed 2-phase flow, plan -> execution.

Stage ordinals are positions within the selected flow. Phase names and artifact filenames come from
the descriptor. For `executor-oneshot`, `stage2` is execution and writes `stage2-execution.md`.

Artifacts and summaries use phase-keyed v2 schemas:

- `cog.executor.artifacts.v2` emits `phases[]` entries with `ordinal`, `phase`, `artifact`, and
  `path`.
- `cog.executor.summary.v2` renders stage status by flow ordinal and includes each stage's `phase`
  and `artifact`.

## Consequences

- Good: `executor-oneshot` can share the same deterministic mechanics as `executor-vetted`.
- Good: CLI identity now matches the skill taxonomy: executor names are routines, engines are coding
  agents.
- Good: future executor flows can add or remove phases by extending the descriptor instead of
  forking artifact and summary logic.
- Cost: consumers of the old v1 fixed artifact keys and `--plan-engine` flag must migrate in lockstep
  with the schema bump.

## Status

Accepted. The descriptor mechanism stands; the specific per-executor flow definitions and the
`cog.executor.summary.v2` schema are superseded by
[ADR-0036](0036-executor-input-quality-gate.md) (gated 2-phase flow, summary v3).
