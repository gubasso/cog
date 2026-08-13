# ADR-0011: Use a trust-gated plan vault

## Context and Problem Statement

Generated plans need global and project-local storage without ambiguous resolution or unsafe local adoption. Moving repositories and identity collisions must remain recoverable.

## Considered Options

- Repository-only plans
- One global flat store
- Global and trusted local vaults with whole-store resolution

## Decision Outcome

Chosen option: `Use global and trusted local vaults with whole-store resolution` — it supports reusable plans while failing closed on untrusted local state.

## Consequences

- Resolution is deterministic across stores.
- Project identities may extend on collision and preserve prior roots.

## Status

Superseded

Superseded by [ADR-0032](./ADR-0032-remove-the-plan-vault-and-the-round-layer.md) — cog no longer stores, queues, splits, or calibrates plans. The surfaces this record enacted are removed; the record is kept for its history.
