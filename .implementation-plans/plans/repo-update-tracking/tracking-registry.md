# Tracking Registry: A Descriptive Periodic-Revalidation Data File + Runbook

> Plan: repo-update-tracking | Round: 1 of 2 | Complexity: M | Generated: 2026-06-19 |
> Repo: /workspaces/cog

## Context

Some repository facts are perishable and must be periodically re-researched (the clearest case being
the model/effort evidence in `docs/reference/models-reference-{claude,codex}.md`, which already
drifted once — Opus 4.7 vs 4.8 — because nothing tracked it). `cog` has no machine-readable record of
*which* artifacts need revalidation, *how often*, *how*, and *what depends on them*.

This round creates that record: a single **tracking registry** data file (YAML, with descriptive
fields) plus a short runbook explaining the format and the revalidation workflow. The registry is the
queryable index a sweep consults; `cog tracking-scan` (Round 2) computes overdue-ness from it.

## Previous Rounds

This is the first round of this plan. It assumes the sibling plan `model-effort-policy-and-rename`
produced `docs/reference/models-reference-claude.md` and `…-codex.md` (each carrying `Data
collected:`, `Revalidate by:`, and `Sources:` metadata) and `docs/reference/model-effort-policy.md` —
the first artifacts to register. It also assumes the sibling `docs-design-tracking-principle` plan
defines the general pattern; if present, mirror its field vocabulary.

## Scope of This Round

- IN scope:
  - Create the tracking registry data file (YAML) with descriptive per-entry fields.
  - Seed it with the model/effort reference entries (and the policy, which is revalidated when its
    evidence is).
  - Write a short runbook (`docs/guides/`) explaining the format, cadence semantics, and the
    revalidation workflow (research → update artifact → bump the registry entry).
  - Index the runbook in `docs/README.md`.
- OUT of scope:
  - The `cog tracking-scan` command and its tests (Round 2).
  - Any wider sweep automation or CI wiring (Round 2 / future).

## Current State

### Key Files

- `/workspaces/cog/docs/reference/` — destination for a reference-style data file is plausible, but a
  tracking registry is repo-maintenance metadata. Place the data file where `cog tracking-scan` (Round
  2) will read it; recommended `docs/reference/maintenance-tracking.yaml` (lookup facts). Confirm the
  final path with Round 2 so both agree.
- `/workspaces/cog/docs/guides/` — Diátaxis "guides" (runbooks), per `AGENTS.md` §"Documentation
  Maintenance". Destination for the revalidation runbook.
- `/workspaces/cog/.implementation-plans/queue-*.yaml` — existing YAML data shape to mirror for
  style (two-space indent, simple scalar lists).
- The model/effort reference files (from the sibling plan) carry `Data collected: 2026-06-19` and a
  `Revalidate by:` cadence — use those as the seed values.

### Existing Patterns

- YAML data files in this repo use two-space indentation and quoted strings only where needed.
- Fenced code blocks need a language (MD040).
- Diátaxis: data/registry = `docs/reference/`; runbook = `docs/guides/`; `docs/README.md` is index
  only.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: tracking-registry`) `status` to `doing`.

### Step 1: Create the tracking registry data file

Create `docs/reference/maintenance-tracking.yaml` with a descriptive schema. Each entry names a
perishable artifact and carries enough description for an agent to act without extra context:

```yaml
# Registry of perishable artifacts that need periodic re-research / revalidation.
# `cog tracking-scan` reports entries whose (last_checked + cadence_days) is in the past.
schema_version: 1
entries:
  - id: models-reference-claude
    path: docs/reference/models-reference-claude.md
    last_checked: 2026-06-19
    cadence_days: 90
    owner: model-effort policy
    why: "Claude model pricing, benchmarks, and available tiers change; the model/effort policy rests on them."
    revalidate_how: "Web-research official Anthropic sources; update figures + Data collected date; re-derive policy if tiers shift."
    references:
      - docs/reference/model-effort-policy.md
      - docs/reference/model-effort-claude.toml
  - id: models-reference-codex
    path: docs/reference/models-reference-codex.md
    last_checked: 2026-06-19
    cadence_days: 90
    owner: model-effort policy
    why: "Codex-selectable GPT models, pricing, and effort multipliers change; the codex policy rests on them."
    revalidate_how: "Web-research official OpenAI/Codex sources; update figures + Data collected date; re-check the -codex API-only caveat."
    references:
      - docs/reference/model-effort-policy.md
      - docs/reference/model-effort-codex.toml
```

Keep field names descriptive (`why`, `revalidate_how`, `references`) so the file is self-documenting
for an AI agent. Align `cadence_days` with each artifact's `Revalidate by:` line.

### Step 2: Write the revalidation runbook

Create `docs/guides/maintenance-tracking.md`: explain the registry's purpose and fields; the cadence
semantics (`last_checked + cadence_days` vs today); the revalidation workflow (run `cog tracking-scan`
→ pick overdue entries → execute each entry's `revalidate_how` → update the artifact's `Data
collected` → bump the entry's `last_checked`); and how to add a new tracked artifact. Forward-
reference `cog tracking-scan` (Round 2).

### Step 3: Index the runbook

Add a one-line entry for the runbook to `docs/README.md` (index only).

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: tracking-registry`) `status` to
   `done`.

## Acceptance Criteria

- [ ] `docs/reference/maintenance-tracking.yaml` exists with a `schema_version`, an `entries` list,
      and descriptive fields (`why`, `revalidate_how`, `references`, `cadence_days`, `last_checked`).
- [ ] It is seeded with the Claude and Codex model-reference entries pointing at their
      `docs/reference/` model-effort consumers.
- [ ] `docs/guides/maintenance-tracking.md` documents the format and the revalidation workflow and is
      indexed in `docs/README.md`.
- [ ] All fenced code blocks declare a language (MD040 clean).
- [ ] This plan's `queue-rounds.yaml` shows round `tracking-registry` as `done`.

## Next Round

`tracking-sweep-tooling` adds the deterministic `cog tracking-scan` command that reads this registry
and reports overdue entries, with tests and an `AGENTS.md` sweep cue.
