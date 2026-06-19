# Round 2: review-loop handoff cog commands

> Plan: review-deep-loop-refactor | Round: 2 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

The prex Stage 5 handoff JSON and `review-loop`'s child-run-dir discovery are deterministic routines
currently written as prose. Move them into `cog` so the schema has a real owner and the skills stay
lean (ADR-0008).

## Previous Rounds

Round 1 refactored `review-code-deep` as the stage-4 skill.

## Scope of This Round

**IN scope:**

- A `cog review-loop-input` subcommand (new `lib/commands/cmd_review_loop.sh` or an extension of an
  existing review command, + `cog::fn::*`) that OWNS the handoff-JSON schema: assemble
  `{task, reviewed_plan, stage4_review, plan_thread_id, impl_thread_id}` from named run-dir files and
  write `review_loop_input.json`; plus a `validate` mode for the schema (missing files, bad/empty
  thread ids → legible failure). This becomes the single schema owner.
- A child-run-dir locate command (e.g. `cog review-loop child-locate` or a `cog rundir locate-child`
  helper) that owns the snapshot/`find … -name 'review-loop-*'`/`comm`/`diff` discovery currently in
  prex Stage 5 prose, returning the new child run dir deterministically.
- Sync `cli-commands.md`, man, completions, help snapshots; add bats covering schema assembly,
  validation, missing files, and child discovery.

**OUT of scope:**

- Rewriting the `review-loop` body (Round 3).
- Rewiring prex Stage 5 (owned by `executor-prex-refactor`).

## Deterministic vs Probabilistic

- Deterministic (cog): the entire JSON assembly/validation + child-run discovery — this whole round.
- Judgment: command naming + where the subcommand lives.

## Validation

- bats green for `cog review-loop-input` (assembly + validation + missing/bad inputs) and child
  discovery. Surfaces in sync. `just lint` + `just test` green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
