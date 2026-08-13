# Executors

Executors prepare one prompt or plan and run it through a bounded implementation contract. [ADR-0010](../decisions/ADR-0010-executor-preparation-and-artifacts.md) owns the principal choices; [ADR-0032](../decisions/ADR-0032-remove-the-plan-vault-and-the-round-layer.md) removed the round layer and the match telemetry that once wrapped them.

## Components and boundaries

Input assessment routes thin requests through planning and lets detailed plans proceed to reviewed execution. Cog owns stage artifacts, collision guards, terminal summaries, and verification.

An executor takes one plan or prompt and records no outcome data. Which executor to run is the caller's judgment rather than a graded lookup.

## Current constraints

A terminal result is explicit, not inferred from missing work. Artifacts use absolute run-directory paths where required, and review effort follows governed model-effort policy.

## Unresolved

- Choosing an executor is unassisted judgment; whether that wants deterministic support again is open.
