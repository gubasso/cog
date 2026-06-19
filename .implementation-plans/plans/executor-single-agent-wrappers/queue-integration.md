# Round 4: queue integration

> Plan: executor-single-agent-wrappers | Round: 4 of 4 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Make all three executors usable as queue prompts so `runner-queue` (the `runner-*` orchestrator) can
dispatch each queue element to the executor named in its `prompt:` field — the user's "executors
alongside executor-prex" requirement.

## Previous Rounds

Round 1: `cog executor`. Round 2: `executor-codex-session`. Round 3: `executor-claude`.

## Scope of This Round

**IN scope:**

- Update `runner-queue` resolution + docs so a queue element's `prompt:` may select any executor:
  `/executor-prex …`, `/executor-claude …`, `/executor-codex-session …`. Confirm
  `cog runner-queue-resolve-plan` (and the queue helpers) recognize the new prompt forms; extend the
  resolver/queue-prompt recognition (built in Round 1) if needed.
- Add queue examples (prompt-driven executor selection) to the relevant docs/reference and the
  `runner-queue` skill prose. Validate no nested plan dirs are introduced (flat-layout guard).
- Run `cog skill-lint` on `runner-queue` if its prose changed; sync any touched command surfaces.

**OUT of scope:**

- `executor-prex` itself (owned by `executor-prex-refactor`); this round only ensures the queue can
  name it alongside the new wrappers.

## Deterministic vs Probabilistic

- Deterministic (cog): the resolver/recognition + flat-layout guard.
- Judgment: example design; how `runner-queue` prose documents executor selection.

## Validation

- `runner-queue` resolves a queue whose elements name different executors; flat-layout guard passes.
  Surfaces in sync. `just lint` + `just test` green. Marks plan `executor-single-agent-wrappers` done
  in the top-level queue as the final round.

## Execution Discipline

One round per `/prex` session; flip this round `done`, set the plan `done` in the top-level queue, and
stop. Commit with `/gc -a` afterward.
