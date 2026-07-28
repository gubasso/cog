# ADR-0056: Plan-round executor-routing contract

## Context and Problem Statement

The complexity rubric ([ADR-0049](./0049-plan-complexity-rubric.md)) grades a round and `cog power-grade match` ([ADR-0054](./0054-executor-capability-grading.md)) routes a score to an executor, but nothing carried that match to execution: `cog power-grade match` had zero consumers and producers hardcoded `/executor-prex` into every round. We need a deterministic contract that lands the matched executor in the queue without re-entangling runners with grading.

## Considered Options

- A separate `executor:` queue field that runners read and dispatch.
- Runners call `cog power-grade match` at dispatch time.
- Producers stamp the matched executor verbatim into each round's `prompt:`, assembled by `cog`.

## Decision Outcome

Chosen option: **producers stamp the matched executor verbatim into the round `prompt:`** — runners stay producer-blind and verbatim ([ADR-0030](./0030-runner-verbatim-queue-dispatch.md)), and all match/assembly judgment stays at the build altitude.

A plan producer, per final round, takes the rubric score → `cog power-grade match` → executor, then `cog round-prompt build --executor <e> --round-path <abs>` assembles `prompt: "/<executor> -ar
<round-path>"`. The build fails closed on an unknown or reserved executor. A reserved round (`score > 30`, `executor: null`) is **never queued**: it routes back through `plan-split`, and a still- reserved irreducible round fails closed to the operator (DP4) rather than falling back to `executor-prex`. The producer-side queue validator runs `cog round-prompt validate` on every `rounds` entry — this validation is part of this decision, not a follow-up. The top-level ledger entry stays `/runner-plan -ar @<plan-dir>/`.

## Consequences

- Good: `cog power-grade match` reaches execution; runners are untouched and producer-blind; legacy `/executor-prex` queues remain valid.
- Good: the feedback arm ([ADR-0058](./0058-match-outcome-telemetry-and-calibration-loop.md)) consumes these match results to judge whether routing was right in practice.
- Bad: producers must own complexity grading, matching, and split routing — a heavier build path.
- Note: the legacy `plan-writer-multi` (Claude) and `plan-writer` (Codex) authoring surfaces are **deleted outright** in this change (operator decision, beyond [ADR-0020](./0020-remove-superseded-skills-and-migration-shims.md) auto-scope), to be re-created from scratch later; tracked in `data/maintenance-tracking.yaml`.

## Status

Accepted.

Will flip to Implemented with code links to [cmd_round_prompt.sh](../../lib/commands/cmd_round_prompt.sh), [fn_round_prompt.sh](../../lib/functions/fn_round_prompt.sh), and `skills/claude/plan-builder-to-queue/SKILL.md` once the routing tests pass.
