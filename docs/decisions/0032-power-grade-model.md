# ADR-0032: Power Grade Model

## Context and Problem Statement

ADR-0013 defines model/effort policy, but `cog` also needs a structured way to compare
model/effort capability and later match executor capacity to work complexity. Markdown-only
`S`/`M`/`L` grading is not machine-readable and has led to oversized executor choices for small work.

## Considered Options

- Keep model/effort policy as prose and provider TOML only.
- Add an evidence-backed Power Grade matrix and CLI lookup command.
- Wait until the future complexity rubric exists before grading model profiles.

## Decision Outcome

Chosen option: **Add an evidence-backed Power Grade matrix and CLI lookup command** - profile power
must be structured before executor capability and complexity cross-match rules can be built.

`docs/reference/power-grade-matrix.toml` is the profile SoT. It uses a 1-10 grade scale, one profile
per executable model/effort cell, explicit `source_refs`, and non-fatal `needs_verification`
evidence markers for genuine public-data gaps. Unsupported effort combinations are not emitted as
executable cells. The matrix also owns the compound-pass formula:
`capped_max_plus_artifact_gain`, capped at the scale maximum.

`cog power-grade` is the deterministic CLI over the matrix. It validates the schema, returns one
cell, classifies profiles that can handle a grade, and compounds pass sequences by reading the
matrix `[compound]` table.

ADR-0032 references ADR-0013 and does not supersede it: ADR-0013 remains the model/effort policy,
while this ADR adds the profile capability layer used by later Power Grade phases.

## Consequences

- Good: Profile grades, validation severity, and compound math are reviewable and testable.
- Good: Later executor and complexity work can consume `cog power-grade` instead of re-parsing docs.
- Bad: Grades still need periodic revalidation because model benchmarks, pricing, and effort
  behavior drift.

## Status

Implemented by `docs/reference/power-grade-matrix.toml`, `lib/functions/fn_power_grade.sh`, and
`lib/commands/cmd_power_grade.sh`.
