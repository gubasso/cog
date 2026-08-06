# Plan vault

The plan vault stores machine-oriented plan and round queues outside the reviewed roadmap. [ADR-0011](../decisions/0011-plan-vault-storage-and-resolution.md), [ADR-0012](../decisions/0012-queue-execution-and-reconciliation.md), and [ADR-0015](../decisions/0015-executor-capability-and-telemetry.md) own its storage, queue, and routing choices.

## Components and boundaries

Global and trusted project-local stores resolve whole plans and queues through stable project identity. Queue selectors treat prompt text as opaque, honor dependencies, and protect completed history during reconciliation.

`docs/plan/` is the reviewed roadmap and single slice-status surface. `.implementation-plans/` and XDG plan stores are execution queues; an item appears in the roadmap only after deliberate adoption as a slice.

## Current constraints

Local stores fail closed until trusted. Plan directories remain flat under their store, collisions extend identities deterministically, and empty outcomes are first-class results.

## Unresolved

- Cross-store archival policy is not yet standardized.
