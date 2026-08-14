# Cog — Charter

## What this is for

Cog provides deterministic mechanics for agent-oriented development workflows while leaving sequencing and judgment to runtime skills and agents. The reviewed roadmap lives here.

Cog does not own a plan vault, execution queues, round sizing, spec production, or executor match telemetry; [ADR-0032](../decisions/ADR-0032-remove-the-plan-vault-and-the-round-layer.md) retired all five. Plan authoring, plan review, and executors remain in scope, and a plan is one artifact under the run-directory root.

## Pillars

- Deterministic, machine-facing contracts.
- Repository self-containment.
- Bounded context at real isolation boundaries.
- Recoverable user state and explicit mutation scope.

## No-gos

- An unattended autonomous scheduler.
- Hidden dependencies on external local repositories.
- Duplicated sources of truth between the plan zone and any generated artifact.
- Workflow-engine implementation while the engine is still being defined outside the record.

## Appetite unit

Implementation sessions. One session is one bounded agent implementation run and its verification.
