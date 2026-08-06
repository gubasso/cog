# Maintenance tracking

This runbook revalidates perishable repository facts registered in `data/maintenance-tracking.yaml`. Registry field definitions, the overdue calculation, and the admission test for a new entry are owned by [documentation mechanics](../explanation/documentation.md).

## Start state

Run from the repository root with network access to the authoritative sources named by the selected entry. Inspect the entry's `path`, `references`, `why`, and `revalidate_how` before editing.

## Revalidate

1. Run `cog tracking-scan --registry "$PWD/data/maintenance-tracking.yaml" --json`.
2. Choose one overdue entry.
3. Follow its `revalidate_how` procedure using primary sources.
4. Update the tracked artifact and every existing target under `references`.
5. Update `last_checked` only for facts actually revalidated.
6. Run the artifact's focused checks, `cog tracking-scan --registry "$PWD/data/maintenance-tracking.yaml" --json`, and the registry existence sweep in [documentation mechanics](../explanation/documentation.md), because `cog tracking-scan` never resolves a `path` or a `references` target.

## Verification

The selected entry is no longer overdue, every `path` and `references` target exists, and the changed artifact's tests or lint gates pass.

## Stop conditions

Stop without changing `last_checked` when an authoritative source is unavailable, ambiguous, or contradicted. Record the uncertainty in the owning plan or review instead of guessing. Roll back only the incomplete documentation edit; do not erase prior research history.
