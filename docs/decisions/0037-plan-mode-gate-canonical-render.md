# ADR-0037: Plan-Mode Gate Lives on the Orchestrator Layer, Rendered From One Source

## Context and Problem Statement

[ADR-0015](0015-plan-skills-not-in-plan-mode.md) put a Phase 0 plan-mode gate on every plan-emitting
skill and could only lint for the marker, not the prose — so the wording drifted across eleven skills.
Two facts reframe the placement: (1) plan mode is a top-level-session property delivered only to the
running model's own context, so a worker invoked via the Agent tool runs in a fresh subagent that never
sees plan mode — its gate is dead there; (2) gating is an entry-point concern that belongs to whoever
drives the work, not to the reusable plan/review worker.

## Considered Options

- Keep the gate on every plan-emitter; lint only the marker (status quo, drifts).
- Keep the gate on workers but make it a cog-rendered single source of truth.
- Move the gate to the executor-*/runner-* orchestrator layer and render it from one source.

## Decision Outcome

Chosen option: **the gate lives on the executor-*/runner-* orchestrator layer, rendered from a cog
single source of truth.** The caller gates once at entry, then delegates to gate-free plan/review
workers. `cog plan-mode-gate render --skill <name>` owns the canonical stanza; `cog-skill-creator`
stamps it; `cog skill-lint` requires every Claude executor-*/runner- skill to carry the canonical gate
(whitespace-normalized exact match) and forbids the gate on every other Claude skill. This supersedes
ADR-0015's placement (gate detection and the cheap-fail goal are unchanged).

## Consequences

- Good: Plan/review workers are clean; the gate is centralized on the orchestrators a user launches, and
  cannot drift (cog-rendered, lint-enforced).
- Good: Self-propagating — a new executor-*/runner- skill must carry it; anything else may not.
- Bad: A plan/review worker invoked **directly** in plan mode no longer prints the friendly exit message
  (the harness still blocks the write); users drive writes through an executor/runner.

## Status

Implemented

Enacted by `lib/functions/fn_skill.sh` (`cog::fn::skill::plan_mode_gate_*`,
`requires_plan_mode_gate`), `lib/commands/cmd_plan_mode_gate.sh`, and the `plan-mode-gate` rule in
`lib/commands/cmd_skill_lint.sh`. Supersedes the placement decision in ADR-0015.
