# Commit orchestration

Commit orchestration partitions explicit session changes by repository and applies safety checks before any mutation. [ADR-0018](../decisions/ADR-0018-safe-commit-orchestration.md) owns the workflow.

## Components and boundaries

Cog scans repository ownership, dirty state, declared paths, message policy, and failure logs. A coordinator fans out per-repository workers and reconciles their structured outcomes. Fix loops classify hook failures and keep provenance visible.

## Current constraints

Foreign dirty state stops the workflow. Conventional commit validation is deterministic, force push is unsupported, destructive recovery requires operator direction, and an empty commit result is valid.

## Unresolved

- Repository-specific hook behavior can still require an operator-authored recovery choice.
