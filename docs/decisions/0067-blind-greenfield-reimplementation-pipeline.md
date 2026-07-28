# ADR-0067: Blind greenfield reimplementation pipeline

## Status

Accepted

## Context

`plan-refactor-migration` covers migration and port-style planning. That shape is not appropriate for from-scratch builds in a different stack because the same worker can see source details and target design, which encourages copied command surfaces, source idioms, and stack-specific assumptions.

Greenfield work needs a firewall: one extractor may observe a source project, but downstream workers must receive only sanitized capability artifacts.

## Considered Options

1. Extend `plan-refactor-migration`.
2. Build one larger `plan-*` skill for the full flow.
3. Build a blind phase pipeline with role-blind workers and a deterministic leakage validator.

## Decision

Build the blind phase pipeline. `plan-refactor-migration` is superseded for greenfield reimplementation work, but remains in place until a separate removal or replacement follow-up.

The pipeline uses a sanitized capability spec, a solution spec, blind reviewers, and `cog spec-leakage-scan` as a deterministic artifact validator.

## Consequences

Good:

- Downstream workers design from behavioral capability rather than source implementation shape.
- Leakage checks are explicit, reusable, and data-driven.
- The public/private artifact split gives the orchestrator source-aware validation without passing source tokens to design workers.

Bad:

- The workflow adds skills, contracts, and a new validator command.
- Sanitizing interface detail can thin subtle edge behavior. Final acceptance proves conformance to the written spec, not equivalence to the source project.
