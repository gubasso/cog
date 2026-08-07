# 001 — Documentation architecture reset

## Goal

A fresh maintainer can find current design, rationale, exact contracts, and ordered work without consulting the draft workspace.

## Appetite

3 implementation sessions. Chosen before the design below.

## Core

The 22-record ADR corpus, 93-row migration ledger, 37-row promotion ledger, deterministic lint gate, and byte-preserving archive proof. This core leaves room for explanatory depth to be cut.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Deepen subsystem pages beyond the minimum component and constraint map.
- Retain the cog-specific `documentation.md` explanation page if its boundary remains useful.
- Polish cross-zone navigation. This item is cut first.

## Out of scope

- Workflow-engine implementation or approval.
- Removal, deprecation, or renaming of the tier concept.
- Deletion of `.draft/` or its manual hand-off buffer.

## Governed by

- `skill-refs/docs-design/02-lean-adrs.md` — decision lifecycle and word cap.
- `skill-refs/docs-design/07-plan-and-slices.md` — plan and slice contracts.
- `skill-refs/docs-design/10-lean-markdown.md` — structural Markdown rules.
- `docs/decisions/ADR-0001-adopt-documentation-architecture.md` — local adoption and reset exception.
- `docs/reference/documentation-migration.md` — exact migration ownership.

## Acceptance

```text
When documentation is validated, the system shall enforce the lean structural contract. -> test/unit/cmd_docs_lint.bats
When the install round-trip runs, the system shall install and manifest-own the imported docs-design digest. -> test/e2e/install_roundtrip.bats
When command surfaces are checked, the system shall keep help, completion, and man command inventories aligned. -> test/integration/help_snapshots.bats
```

## Rabbit holes

- Broad link churn can hide a wrong in-range ADR rewrite — escape: rewrite from the disposition ledger and spot-check each subject before proceeding.
- Subsystem pages can grow into duplicate ADRs — escape: keep current design here and link rationale once.

## Done when

The named tests and full gates pass before and after all 37 sources move byte-for-byte under `.draft/safe-to-delete/`, and milestone 001 flips to `done`.

## Revisions

Bootstrap deviation: this slice was committed as part of its own implementation after the initial inventory and architecture import had begun; ADR-0001 and the migration ledger preserve that exception.
