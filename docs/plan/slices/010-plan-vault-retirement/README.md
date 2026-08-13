# 010 — Plan vault retirement

## Goal

Cog holds no plan vault, no execution queues, no round layer, and no executor match telemetry, while plan authoring, plan review, and every executor keep working.

## Appetite

3 implementation sessions. Chosen before the design below.

## Core

Every surviving plan producer, plan reviewer, and executor still runs after the vault, the queues, the round layer, and the telemetry surface are gone, leaving prose and naming cleanup as remainder.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Decouple the survivors first: default plan artifacts to a run directory, drop the vault-shaped `MODE=dir` review input, and strip `cog match-telemetry` from the four executors that call it.
- Retire the fourteen vault, round, and spec-pipeline skills and the `runner` skill class across every code, data, and prose surface that enumerates it.
- Retire the twenty-three commands, thirteen functions, and the executor-capability half of `cog power-grade`, regenerating the four mirrored command surfaces in one commit.
- Retire the vault tree, its documentation, and its records, flipping four ADRs terminal rather than deleting them. Prose breadth is cut first.

## Out of scope

- Re-keying executor telemetry onto a surviving identifier.
- The provider-runner surface, `cog codex-runner`, and slices 004-009.

## Governed by

- `docs/decisions/ADR-0032-remove-the-plan-vault-and-the-round-layer.md` — what is retired and why nothing replaces it.
- `docs/decisions/ADR-0010-executor-preparation-and-artifacts.md` — the executor behavior that must survive.
- `docs/reference/skill-contract.md` — the skill-class and prefix rules the `runner` retirement edits.
- `docs/explanation/architecture.md` — the component boundaries left after removal.

## Acceptance

```text
When a plan producer saves a default artifact, cog shall resolve an output path under the run-directory root and not under a repository-relative store. -> test/integration/plan_doc.bats
When the vault, queue, round, and telemetry surfaces are removed, cog shall start, expose no retired command, and keep its help, completion, and man surfaces in sync. -> test/integration/help_snapshots.bats
When the runner skill class is retired, skill-class resolution shall reject it and skill-lint shall pass over the surviving classes. -> test/integration/cmd_skill_lint.bats
```

## Rabbit holes

- A bare `runner` sweep can destroy the provider-runner surface slice 006 is building — escape: every search is anchored to a queue-runner identifier, never a bare word.
- Deletion can outrun decoupling and leave a daily-driver skill transiently broken — escape: change and decouple every survivor before removing anything.
- A name match can take out a surviving artifact — escape: an artifact is removed only if it exists to serve the vault, and the retirement record names the survivors explicitly.

## Done when

The named tests above pass unskipped, no retired identifier remains outside closed slice 003 and generic design prose, and the `milestones.md` line flips.

## Revisions

None.
