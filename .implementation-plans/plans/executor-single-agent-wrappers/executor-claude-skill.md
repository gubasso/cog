# Round 3: /executor-claude skill

> Plan: executor-single-agent-wrappers | Round: 3 of 4 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Author the Claude-side single-agent executor on top of the Round-1 `cog executor` mechanics. It runs
the native Claude execution path and embeds the 3-stage flow with the OTHER engine reviewing.

## Previous Rounds

Round 1 built `cog executor`. Round 2 authored `executor-codex-session`.

## Scope of This Round

**IN scope:**

- `skills/claude/executor-claude/SKILL.md`: frontmatter `name: executor-claude`, `argument-hint`,
  `trigger-tests`, model/effort per `model-effort-policy.md`. Body = sequencing + judgment: accept a
  prompt OR a plan path; run the 3-stage flow via `cog executor`:
  - Stage 1 → `/plan-claude` (skip if a plan is supplied).
  - Stage 2 → `/review-plan-codex` (the OTHER engine reviews a Claude-made plan).
  - Stage 3 → execute the reviewed plan via the native Claude path, carrying relevant session context.
  - Emit the executor summary via `cog executor`.
- Plan-mode gate decision (ADR-0015): if `executor-claude` writes a plan artifact directly it carries
  `<!-- cog-skill: plan-emitter -->` + the Phase 0 gate; if all plan emission is delegated to
  `/plan-claude` (which already gates), document that the gate lives in the delegated skill. Decide and
  record per the `skill-prefix-taxonomy` rule.
- Foreground delegation only; never background orchestration (ADR-0010).
- Run `cog skill-lint` (structural + plan-mode-gate as applicable + orchestration).

**OUT of scope:**

- Queue wiring (Round 4).

## Deterministic vs Probabilistic

- Deterministic (cog): the 3-stage sequencing via `cog executor`.
- Judgment: Stage-1 skip, session-context selection for Stage 3, the gate-location decision.

## Validation

- `cog skill-lint` green (taxonomy + gate rules satisfied). No inline deterministic shell beyond `cog`.
  `just lint` + `just test` green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
