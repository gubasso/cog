# 009 — Installation and retirement

## Goal

Workflow assets install and uninstall completely, and every obsolete skill and reference is absent.

## Appetite

2 implementation sessions. Chosen before the design below.

## Core

The manifest round-trip proves all accepted workflow assets and retirement paths, leaving adjacent install cleanup as negotiable remainder.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Install workflow assets, completion, man entries, and skill-class data through existing whole-tree lanes.
- Assert uninstall removes every manifest-owned workflow asset while preserving user files.
- Add install completeness and stale-reference tests.

## Out of scope

- Workflow feature work beyond packaging.
- Speculative new installer branches where `copy_tree` already owns the subtree.

## Governed by

- `docs/plan/slices/008-orchestration-cutover/README.md` — retirement set.
- `docs/decisions/ADR-0004-manifest-owned-installation.md` — install authority.
- `docs/explanation/installation.md` — current install design.
- `docs/reference/install-layout.md` — exact installed paths.

## Acceptance

```text
When cog installs, the installer shall manifest-own every workflow asset, completion, man entry, and skill-class file. -> test/e2e/install_roundtrip.bats
When cog uninstalls, the uninstaller shall remove only those owned assets and leave user-authored files. -> test/e2e/install_roundtrip.bats
```

## Rabbit holes

- Installer duplication can create a second ownership lane — escape: extend existing whole-tree assertions before adding code.

## Done when

Install and uninstall round-trip, stale-reference checks pass, obsolete surfaces are absent, and milestone 009 flips to `done`.

## Revisions

- 2026-08-13 — In scope and Rabbit holes dropped their `data/spec-leakage/` clauses. ADR-0032 deleted that data subtree, so the missing install coverage it named can no longer be reproduced or fixed.
