# Cog — Charter

<!-- markdownlint-configure-file { "MD043": { "headings": ["# Cog — Charter", "## What this is for", "## Pillars", "## No-gos", "## Appetite unit"] } } -->

## What this is for

Cog provides deterministic mechanics for agent-oriented development workflows while leaving sequencing and judgment to runtime skills and agents. The reviewed roadmap lives here; generated execution queues remain in `.implementation-plans/` and resolved plan-vault stores.

## Pillars

- Deterministic, machine-facing contracts.
- Repository self-containment.
- Bounded context at real isolation boundaries.
- Recoverable user state and explicit mutation scope.

## No-gos

- An unattended autonomous scheduler.
- Hidden dependencies on external local repositories.
- Duplicated sources of truth between the plan zone and plan vault.
- Activation of workflow-engine implementation before slice 002 accepts it.

## Appetite unit

Implementation sessions. One session is one bounded agent implementation run and its verification.
