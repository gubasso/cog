# Power grade

Power grade is the current model, effort, and tier subsystem. [ADR-0014](../decisions/ADR-0014-model-effort-and-power-grade.md) owns the tier ladder and evidence model; [ADR-0032](../decisions/ADR-0032-remove-the-plan-vault-and-the-round-layer.md) removed its executor-capability routing half.

## Components and boundaries

YAML under `data/model-effort/` records governed skill tiers. `data/power-grade/` records model cells and source allowlists. `cog power-grade` exposes validation and lookup operations over those tables.

A cell is one model and effort pairing. A tier names equivalent Claude and Codex cells for policy. A skill resolves to a tier by registry pin first and prefix default second; nothing routes an executor by graded capability.

## Current constraints

Unsupported or unknown efforts are never fabricated. Cleared claims cite registered sources, perishable facts remain tracked, and skill-lint enforces governed tier assignments.

## Unresolved

- New provider evidence can change cell clearing without changing the tier vocabulary.
