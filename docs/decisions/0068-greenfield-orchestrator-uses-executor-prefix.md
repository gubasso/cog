# ADR-0068: Greenfield orchestrator uses the executor prefix

## Status

Accepted

## Context

The greenfield pipeline has a write-capable, staged orchestrator. It interviews, dispatches workers, creates intermediate artifacts, runs setup, hands off to the plan-to-queue tail, and drives implementation. The taxonomy has no governed `pipeline-*` or `orchestrator-*` class. `bootstrap` is an ungoverned precedent, but it predates the current plan-mode gate enforcement.

## Considered Options

1. Use a governed `executor-*` skill under the staged-executor carve-out.
2. Use an ungoverned bootstrap-style skill and add a future `pipeline-*` or `orchestrator-*` class.

## Decision

Use `executor-greenfield-from-spec`. The skill is a governed `executor-*` orchestrator and is pinned to the HIGH tier in the model-effort registry.

This reuses the `executor-prex` precedent for staged execution and lets existing lint enforce the Phase 0 plan-mode gate. The orchestrator also belongs in the curated context-brief and input-fidelity sets because it builds fresh-context worker briefs.

## Consequences

Good:

- No new taxonomy machinery is needed.
- A write-capable entrypoint receives lint-enforced plan-mode gating.
- The existing staged-executor precedent remains the governing shape.

Bad:

- `executor-*` is broader than its narrow "one prompt or plan" wording.
- A future governed `pipeline-*` class may still be useful if the repo grows more write-capable orchestrators.

The rejected ungoverned option leaves a latent write-capable-but-gate-exempt gap unless full lint enforcement for a new class is built.
