# ADR-0069: Right-sizing loop control flow is a cog-owned state machine

## Context and Problem Statement

[ADR-0050](./0050-recursive-round-right-sizing.md) assigns the recursive round right-sizing loop's control flow to a deterministic "orchestrator" role, but that control flow lived in skill prose. A live `plan-builder-to-queue-vetted-multi` run deviated: instead of seeding one parent round and recursively binary-splitting, the coordinator reused the generator's authored `### Round N` sections and materialized many round files up front. Prose the coordinator can reinterpret is not a durable guarantee that the seed is a single parent and that rounds enter only through coverage-checked splits.

## Considered Options

- **Harden the prose.** Add an explicit prohibition against pre-materializing rounds. Cheap, but still reinterpretable — no structural guarantee.
- **A cog-owned loop state machine.** Move the seed, drain, over-ceiling compare, coverage-gated enqueue, termination, and baseline conservation into a `cog` verb the skill advances step by step.

## Decision Outcome

Chosen option: **a cog-owned loop state machine** — `cog round-rightsize` (`init | pending |
record-grade | record-split | reopen | status | finalize`). It fulfils [ADR-0050]'s Orchestrator role; it does not change [ADR-0050]'s three-role, serialized-judgment decision. Judgment (grade, where-to-split) stays in the `review-plan-complexity` evaluator and `plan-split` splitter; the skill only runs those workers on the exact round cog hands back and feeds their structured verdicts in.

The determinism guarantee is structural and enforced by cog at the seam, not by trusting the caller: `init` takes exactly one baseline, **rejects** a baseline that already carries authored `### Round N` sections (a materialized round list), and seeds a one-item queue; no verb accepts a list of rounds; `record-grade` **rejects** a grade that is not backed by a parsing, self-consistent `review-plan-complexity` report (its `grade`/`score` must match the recorded values); and the sole appender is `record-split`, which enqueues exactly two children and only after `round-split coverage` passes. The observed "many rounds up front" deviation is rejected at the seed, and a self-invented grade with no backing report is rejected at `record-grade`.

This is a fail-closed entry/grading guard, not a claim that the model cannot err inside a worker: a model can still author a well-formed report whose grade it decided badly — cog enforces that a report exists, parses, and self-agrees with the recorded grade/score, not that the grade is correct.

Correctness pin: the `score > 30` executor-reserved compare stays out of the loop (Phase 6 `cog
power-grade match`); `reopen` is a bare status flip, so the loop remains executor-independent per [ADR-0050].

## Consequences

- Good: the single-parent seed and coverage-gated binary growth are enforced by cog, not prose.
- Good: judgment stays in workers; the loop is a pure dispatch over their fields ([ADR-0008](./0008-skill-script-boundary.md), [ADR-0009](./0009-machine-facing-output-contract.md)).
- Bad: one more `cog` command and a durable state file to maintain.

## Status

Implemented. `lib/commands/cmd_round_rightsize.sh` and `lib/functions/fn_round_rightsize.sh` provide the state machine; `skills/claude/plan-builder-to-queue/` and `skills/claude/plan-builder-to-queue-vetted-multi/` drive it; the contract is `skill-refs/plan-rounds/round-splitting-contract.md`.
