# Executors

Executors prepare one prompt or plan and run it through a bounded implementation contract. [ADR-0010](../decisions/0010-executor-preparation-and-artifacts.md), [ADR-0013](../decisions/0013-complexity-driven-round-sizing.md), and [ADR-0015](../decisions/0015-executor-capability-and-telemetry.md) own the principal choices.

## Components and boundaries

Input assessment routes thin requests through planning and lets detailed plans proceed to reviewed execution. Cog owns stage artifacts, collision guards, terminal summaries, and verification. Complexity workers judge plans; the round state machine preserves requirement identities and controls recursive splitting.

Capability data derives executor bands. Append-only outcome telemetry records whether assignments were over-, under-, or well-matched; humans approve calibration changes.

## Current constraints

A terminal result is explicit, not inferred from missing work. Artifacts use absolute run-directory paths where required, and review effort follows governed model-effort policy.

## Unresolved

- The rubric maximum remains a follow-up for machine-readable enforcement.
