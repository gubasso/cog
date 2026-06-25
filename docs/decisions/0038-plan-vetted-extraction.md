# ADR-0038: Extract plan-vetted as a Reusable Vetted-Plan Producer

## Context and Problem Statement

[ADR-0036](0036-executor-input-quality-gate.md) gave `executor-vetted` an input-quality gate plus
dual-engine planning: evaluate the input, then generate a plan (`needs-plan` → `/plan-multi`) or
multi-review it (`good-input` → `/review-plan-multi`), producing one vetted `prepared-plan.md`. That
"produce a vetted plan" pipeline was inlined in `executor-vetted` and unavailable to other callers.
`executor-prex` wanted the same capability in place of its two separate planning stages — Stage 1
(Codex drafts via `/plan-oneshot`) and Stage 2 (Claude reviews via `/review-plan-oneshot`).

`executor-prex` Stage 3 implemented by **resuming the Stage 1 Codex planning thread**
(`PLAN_THREAD_ID`/`PLAN_ACCOUNT` → `cog codex-runner run-resume`). A Claude-orchestrated vetted-plan
producer runs its dual engines as fresh-context subagents and yields **no resumable Codex thread**, so
that continuity model could not survive the swap.

## Considered Options

- Keep the gate-plus-prepare pipeline inlined in `executor-vetted`; re-implement it in `executor-prex`.
- Factor it into a new `plan-*` skill that both executors call; give it a parallel `cog plan-vetted`
  command surface.
- Factor it into a new `plan-*` skill that both executors call; reuse the existing `cog executor`
  route→producer registry.

## Decision Outcome

Chosen option: **a new `plan-vetted` skill, reusing `cog executor`.** `plan-vetted` is a gate-free
`plan-*` worker (per [ADR-0037](0037-plan-mode-gate-canonical-render.md) the plan-mode gate stays on
the `executor-*`/`runner-*` caller) that evaluates the input and routes to `/plan-multi` or
`/review-plan-multi`, writing the vetted plan to a caller-supplied `--output`. Both `executor-vetted`
and `executor-prex` inline-chain it (same context, preserving the subagent depth budget); the gate's
heavy producers remain fresh-context Agent-tool subagents inside `plan-vetted`.

The deterministic mechanics reuse the `cog executor` surface rather than a parallel command: a
single-phase `plan-vetted` flow in `cog::fn::executor::flow_json` carries the route→producer table, and
`cog executor export-prepared` copies the canonical `prepared-plan.md` to the caller's `--output`.
`executor-vetted`'s producers repoint to `/plan-vetted`.

For `executor-prex`, the swap collapses old Stages 1+2 into one **Stage 1-2: Vetted Plan**, and Stage 3
implements via a **fresh Codex `exec` with the vetted plan inlined** — there is no planning thread to
resume; continuity comes from the plan text. This is the path the old "Resume Fallback" already
documented, now the only path.

## Consequences

- Good: One vetting pipeline, reused by both executors and runnable standalone as `/plan-vetted`.
- Good: Producer routing stays a single deterministic `cog` table; no parallel command surface.
- Good: `plan-vetted` is gate-free and depth-preserving (inline-chained), consistent with ADR-0037.
- Bad: `executor-prex` loses Codex planning-session continuity into implementation; the inlined vetted
  plan must carry all planning context. Acceptable because the vetted plan is self-contained.
- Neutral: `--executor plan-vetted` names a plan-only flow on the `cog executor` surface (a flow id,
  not a 2-stage executor); it does not emit an executor summary.

## Status

Implemented

Enacted by `skills/claude/plan-vetted/SKILL.md`, the `plan-vetted` flow and `export-prepared` verb in
`lib/functions/fn_executor.sh` + `lib/commands/cmd_executor.sh`, the rewired
`skills/claude/executor-vetted/SKILL.md` and `skills/claude/executor-prex/SKILL.md` (+ references), and
the `claude:plan-vetted` entry in the `input-fidelity` rule of `lib/commands/cmd_skill_lint.sh`.
Builds on ADR-0036; honors ADR-0037 (gate placement) and ADR-0035 (input fidelity).
