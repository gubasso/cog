# ADR-0020: Use reliable classification and composable pre-commit overlays

## Context and Problem Statement

Bootstrap choices depend on project shape, execution environment, and cross-language quality layers. Prose signals and replacement-style hook options create false classifications and broken overlays.

## Considered Options

- Prompt-based classification
- One template per project combination
- Prose-immune classification with environment-aware execution and additive overlays

## Decision Outcome

Chosen option: `Use prose-immune classification with environment-aware execution and additive overlays` — it keeps project detection deterministic while composing Nix, spell, and Markdown policy.

## Consequences

- Ambiguous projects fail visibly.
- Hook execution can enter the project's declared environment.

## Status

Implemented

Enacted by [bootstrap](../explanation/bootstrap.md) and [`cmd_classify_project.sh`](../../lib/commands/cmd_classify_project.sh).
