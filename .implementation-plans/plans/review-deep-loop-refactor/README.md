# Review-deep + review-loop refactor: stage-4 review skill and JSON-out-of-prose

> Complexity: L | Rounds: 3 | Generated: 2026-06-19 | Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Problem Statement

Two `review-*` skills need refactoring so `executor-prex` can DRY-delegate its review stages to real
skills with deterministic mechanics in `cog`:

1. **`review-code-deep`** must be the canonical Stage-4 implementation-review skill. It already has an
   Orchestrator Invocation Contract (two abs paths → JSON findings), which `prex` Stage 4 and
   `review-loop` already invoke. Refactor it (inspired by prex Stage 4's JSON-findings-for-triage
   contract) so the stage-4 use is first-class, and keep its Phase-0 mechanics in the existing
   `cog review-*` commands.
2. **`review-loop`** carries a deterministic flaw the user flagged: prex Stage 5 tells the model to
   "Build a `review_loop_input.json` file … with the following structure { task, reviewed_plan,
   stage4_review, plan_thread_id, impl_thread_id }" — a deterministic JSON assembly written as prose
   in a probabilistic skill. The same applies to the `find … -name 'review-loop-*'` + `comm`/`diff`
   child-run-dir discovery. Both must move into `cog` subcommands, and `review-loop` must consume them.

## Strategy

1. `review-code-deep-stage4-contract` — refactor `review-code-deep` (+ Codex twin) as the canonical
   stage-4 review skill.
2. `review-loop-handoff-cog-commands` — own the handoff-JSON schema + child-run discovery in `cog`.
3. `review-loop-skill-leaning` — rewrite `review-loop` to consume those cog commands; drop the inline
   JSON literal + `find`/`comm` prose.

## Rounds

1. `review-code-deep-stage4-contract.md` — `review-code-deep` (+ codex twin) stage-4 refactor.
2. `review-loop-handoff-cog-commands.md` — `cog review-loop-input` + child-run-dir locate command.
3. `review-loop-skill-leaning.md` — `review-loop` consumes the cog commands; lean body.

## Execution Commands

```bash
/prex -ar @.implementation-plans/plans/review-deep-loop-refactor/
# or
/prex -ar .implementation-plans/plans/review-deep-loop-refactor/review-code-deep-stage4-contract.md
```

## Execution Discipline

One `/prex` session per round; runs the first `todo` round, flips it `done`, stops. Commit each round
with `/gc -a` afterward.

## Decisions & Constraints

- `Executor: prex (EF 1.5)`.
- `review-code-deep` and `review-loop` are `review-*` skills (no rename). `review-code-deep` reviews
  code-vs-codebase+plan; `review-loop` orchestrates iterative code review.
- The handoff JSON schema (`{task, reviewed_plan, stage4_review, plan_thread_id, impl_thread_id}`) is
  currently DEFINED ONLY by the prex-body literal (no schema owner). This plan makes a `cog`
  subcommand the schema owner.
- Deterministic mechanics (JSON assembly/validation, child-run discovery) → `cog`; review judgment
  (triage, termination, finding validation) stays prose.
- `review-loop` keeps its `context: fork` / `agent` frontmatter, handoff + standalone modes,
  MAX_ROUNDS, and triage vocabulary. Codex effort is already native (this plan `depends_on`
  `codex-native-effort-runner`); do not re-do the effort swap.
- New cog commands sync `cli-commands.md`, man, completions, help snapshots, bats. Do not run git
  commands inside round bodies.

## Reconciliation (depends_on, no duplication)

- `depends_on: skill-taxonomy-governance` — confirms both skills sit in `review-*`.
- `depends_on: codex-native-effort-runner` — the effort swap is already done; this plan is structural.
- The runtime `codex-conventions.md`-read removal is owned by `cog-self-contained-skill-refs` — do not
  re-do it; rely on the internalized cog orientation.
- Consumed by `executor-prex-refactor` Stages 4 (review-code-deep) and 5 (review-loop +
  `cog review-loop-input`).
