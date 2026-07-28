# ADR-0034: Power Grade Source ID Enforcement

## Context and Problem Statement

ADR-0013 establishes that deterministic mechanics belong in `cog`, and ADR-0033 establishes the Power Grade benchmark source-tier policy in `docs/reference/power-grade-source-allowlist.toml`. Before this decision, `docs/reference/power-grade-matrix.toml` carried human-readable `source_refs`, but `cog power-grade validate` did not verify that sourced profiles referenced allowlisted source IDs. That left source-tier policy enforceable only by prose review.

## Considered Options

- Keep source-tier checks as manual review.
- Reuse `source_refs` as machine source IDs.
- Add a separate matrix field for allowlist source IDs and validate it in `cog`.

## Decision Outcome

Chosen option: **Add a separate matrix field for allowlist source IDs and validate it in `cog`.**

Each profile in `docs/reference/power-grade-matrix.toml` carries `benchmark_source_ids`, an array of IDs from `docs/reference/power-grade-source-allowlist.toml`. `source_refs` remains the human doc-anchor field. `benchmark_source_ids` is a machine validation field.

`cog::fn::power_grade::validate_json` loads both the matrix and allowlist. It fails on unknown source IDs, warns when a Tier 3 source is cited, and warns when a profile whose `evidence_status` is not `needs_verification` lacks any Tier 1 or Tier 2 source ID. The production matrix is expected to have no Tier 3 source warnings and no sourced-without-allowlisted-source warnings.

This decision references ADR-0013 and ADR-0033 and supersedes nothing.

## Consequences

- Good: source-tier policy is checked by deterministic CLI validation rather than review memory.
- Good: human doc anchors and machine source IDs can evolve independently.
- Good: weak source IDs remain visible as warnings without masking unknown IDs, which are fatal.
- Bad: every profile fixture must carry `benchmark_source_ids`, including empty arrays for intentional `needs_verification` rows.

## Status

Implemented by `docs/reference/power-grade-matrix.toml`, `docs/reference/power-grade-source-allowlist.toml`, and `cog::fn::power_grade::validate_json`.
