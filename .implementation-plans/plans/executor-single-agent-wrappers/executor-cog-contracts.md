# Round 1: executor cog contracts (3-stage sequencing mechanics)

> Plan: executor-single-agent-wrappers | Round: 1 of 4 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Both wrappers share the same deterministic skeleton: a run-dir, named stage artifacts, the 3-stage
sequencing (plan → opposite-engine plan-review → execute), the OTHER-engine selection rule, and
queue-prompt recognition. Build it once in `cog` so the two skills stay lean (ADR-0008).

## Previous Rounds

None (first round).

## Scope of This Round

**IN scope:**

- A `cog executor` command family (`lib/commands/cmd_executor.sh` + `cog::fn::executor::*`) owning:
  run-dir creation; stable stage-artifact names (`stage1-plan.md`, `stage2-reviewed-plan.md`,
  `stage3-execution.md`, `executor-summary.json`); input classification (a prompt vs an already-made
  plan path → run all three stages vs skip Stage 1); the OTHER-engine selection rule (engine that
  produced the plan → which `/review-plan-*` reviews it); and the machine-facing summary. Machine
  output + file-first (ADR-0009).
- Define queue-prompt recognition data so `runner-queue` can dispatch `/executor-claude …` /
  `/executor-codex-session …` prompts (consumed by Round 4 + the `runner-queue` resolver).
- Sync `cli-commands.md`, man, completions, help snapshots; add `test/integration/cmd_executor.bats`.

**OUT of scope:**

- The two `SKILL.md` bodies (Rounds 2–3).
- `runner-queue` wiring (Round 4).

## Deterministic vs Probabilistic

- Deterministic (cog): all sequencing/artifact/selection mechanics — this whole round.
- Judgment: artifact naming + the input-classification heuristic boundary.

## Validation

- `cog executor` bats green (prompt-input runs 3 stages; plan-input skips Stage 1; OTHER-engine rule
  selects the right reviewer). Surfaces in sync. `just lint` + `just test` green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
