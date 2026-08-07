# Power grade

Power grade is the current model, effort, tier, and executor-capability subsystem. [ADR-0014](../decisions/ADR-0014-model-effort-and-power-grade.md) owns the tier ladder and evidence model.

## Components and boundaries

YAML under `data/model-effort/` records governed skill tiers. `data/power-grade/` records model cells, source allowlists, executor passes, calibration, and review evidence. `cog power-grade` exposes validation and lookup operations over those tables.

A cell is one model and effort pairing. A tier names equivalent Claude and Codex cells for policy. Capability bands derive executor routing without erasing the underlying tier concept.

## Current constraints

Unsupported or unknown efforts are never fabricated. Cleared claims cite registered sources, perishable facts remain tracked, and skill-lint enforces governed tier assignments.

## Unresolved

- New provider evidence can change cell clearing without changing the tier vocabulary.
