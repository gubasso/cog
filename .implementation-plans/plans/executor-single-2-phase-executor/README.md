# executor-single + decouple `cog executor` stages from phases

> Complexity: L | Rounds: 1 | Generated: 2026-06-22 | Repo: /workspaces/cog

## Problem Statement

`cog`'s executor family runs one prompt/plan through a coding agent. `executor-lean` runs three
phases (plan → review-plan → execute). We are adding **`executor-single`**, a 2-phase routine
(plan → execute) that drops the plan-review phase, shipped as a native twin pair plus a Claude→Codex
delegation launcher (mirroring the `executor-lean` trio).

Building it requires fixing two structural problems in `cog executor`:

1. **Stage ordinals are hardwired to phase meaning** (`stage1=plan`, `stage2=reviewed-plan`,
   `stage3=execution`) throughout `lib/functions/fn_executor.sh`. A 2-phase executor cannot express
   "stage2 = execution" without forking. Fix: each executor declares its own ordered **phases**;
   ordinals are just positions.
2. **Naming is incoherent**: `cog executor init --executor claude|codex-session` uses "executor" to
   mean the coding agent, but `executor-*` is a skill/routine in the taxonomy. Fix:
   `--executor <skill>` selects the flow, `--engine <claude|codex>` selects the agent, and
   `--plan-engine` is removed.

## Strategy

The user explicitly chose a **single round**: the core `cog executor` refactor, the `executor-lean`
migration, the new `executor-single` skills, the test updates, and the docs/ADR are tightly coupled
(the skills cannot pass `skill-lint`/smoke tests until the new CLI contract exists, and the lean
tests must move in lockstep with the schema bump), so they ship together and are verified as one unit
with `just test` + `just lint` + `cog skill-lint`.

## Rounds

The authoritative order and status live in `queue-rounds.yaml`.

1. `implement-executor-single-and-decouple.md` — flow-descriptor SoT + `executor`/`engine` rename +
   phase-keyed artifacts/summary v2; migrate the `executor-lean` trio; add the `executor-single`
   trio; update `cmd_executor.bats`; ADR + docs.

## Execution Commands

```bash
# Execute the next todo round (executor reads queue-rounds.yaml, runs the first todo round, then stops):
/executor-prex -ar @.implementation-plans/plans/executor-single-2-phase-executor/

# Or target the round file directly:
/executor-prex -ar .implementation-plans/plans/executor-single-2-phase-executor/implement-executor-single-and-decouple.md
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for a
single `/executor-prex` session. Do not implement multiple rounds in one session.

When `/executor-prex` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh `/executor-prex` session is launched for any subsequent round.

## Decisions & Constraints

- **Executor: executor-prex (EF 1.5).**
- **Naming model:** `--executor <executor-lean|executor-single>` = skill/routine (selects flow);
  `--engine <claude|codex>` = coding agent (selects plan engine + reviewer engine). `--plan-engine`
  is removed. An `executor-*` is never a coding agent.
- **Flow descriptor is the SoT.** `cog::fn::executor::flow_json <executor-name>` declares each
  executor's ordered phases (ordinal → phase → artifact → skippable). The plan phase is the skippable
  one (skipped on plan input), derived from `phase==plan`, not the ordinal.
- **Schema v2.** Artifacts/summary JSON becomes generic phase-keyed (`phases[]`); both bumped to v2.
  Only tests consume the JSON shape — skills use literal filenames — so no external migration.
- **`executor-single` artifact** for the execute phase is `stage2-execution.md` (not `stage3-*`).
- **Full trio shipped:** native `executor-single` (claude + codex) + `executor-single-codex`
  launcher; `/executor-single` and `/executor-single-codex` registered in `queue-prompts`.
- **`executor-lean` behavior is unchanged** under the new contract (same 3 phases, same artifacts).
- Lint/policy constraints: `model: sonnet` forbidden (`opus`+`effort: low`); Codex twins carry only
  `name`+`description`; native twins share a base name; the `-codex` suffix is the launcher.

## Rejected Alternatives

- **New `--executor` enum values (`claude-single`, `codex-session-single`)** — rejected: conflates
  engine identity with stage shape and grows the enum per variant; violates the coherent
  executor=skill / engine=agent model.
- **Orthogonal `--flow lean|single` keeping `--engine` only** — rejected: cog never learns the
  routine identity; the skill name should be the executor identity passed to cog.
- **Additive-compat JSON (keep legacy `stage*_*` keys for lean)** — rejected in favor of a clean
  generic phase-keyed v2; the legacy keys are consumed only by tests, which move with the schema.
- **Multi-round split** — rejected by user directive (single round); the pieces are coupled enough
  that one verifiable unit is acceptable.

## Risks & Edge Cases

- **Large single round.** Mitigation: explicit per-step file targets and a final `rg` sweep
  (Step 11) to catch stragglers; verification gates (`just test`, `just lint`, `cog skill-lint`).
- **Hidden consumers of the v1 JSON keys/flags.** Mitigation: Step 11 greps `lib/ skills/ test/
  docs/ completions/ man/` for `stage*_*`, `--plan-engine`, `codex-session`, `summary.v1`.
- **`executor-single-codex` marker drift.** Mitigation: mirror `executor-lean-codex` exactly and
  gate on `cog skill-lint`.
- **ADR number collision.** Mitigation: confirm the next free `docs/decisions/` number at implement
  time (0027 expected, since 0026 is now taken) and bump if taken.
- **`executor-prex` 4-stage hook-guard confusion.** Accepted/avoided: it is a separate flow and is
  explicitly out of scope.

## Completion

When the round is done, set it `done` in this plan's `queue-rounds.yaml` and set this plan `done` in
the top-level `.implementation-plans/queue-plans.yaml`. Nothing moves on disk.
