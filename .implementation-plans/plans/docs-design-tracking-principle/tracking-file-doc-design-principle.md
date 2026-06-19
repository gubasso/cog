# Add the Tracking-File / Periodic-Revalidation Docs-Design Principle

> Plan: docs-design-tracking-principle | Round: 1 of 1 | Complexity: S | Generated: 2026-06-19 |
> Repo: /workspaces/cog (writes to $DOCS_NOTES_REPO)

## Context

Documentation often holds perishable facts (benchmarks, prices, model rosters, API shapes) that drift
silently. The docs-design shelf at `$DOCS_NOTES_REPO/tech/programming/docs-design/` codifies reusable
documentation patterns (Diátaxis zones, lean ADRs, single-source-of-truth, drafts/promotion,
operational docs, AI-agent considerations) but has **no principle for tracking files**: a
machine-readable registry that records which artifacts need periodic re-research, the cadence, the
revalidation procedure, and the downstream dependents — so coding agents (primary audience) and
humans can flag and refresh stale content during a normal codebase sweep.

This round adds that principle. It is the generalized form of the concrete tracker `cog` builds in
the `repo-update-tracking` plan (`docs/reference/maintenance-tracking.yaml` + a `cog tracking-scan`
command), which this principle cites as a worked example.

## Previous Rounds

This is the first and only round. It is independent of the cog-internal plans but pairs with
`repo-update-tracking` (the concrete instance) and references the SoT principle already on the shelf
(`04-single-source-of-truth.md`).

## Scope of This Round

- IN scope (all under `$DOCS_NOTES_REPO/tech/programming/docs-design/`):
  - A new principle file (next free number before `99-checklist.md`, expected
    `08-tracking-and-revalidation.md`).
  - Update `README.md` (shelf index), `AGENTS.md` (digest + last-synced date), and `99-checklist.md`
    (add a tracking/revalidation check).
- OUT of scope:
  - Any change to the `cog` repo source (only this plan's `.implementation-plans/` metadata lives in
    cog).
  - Building tooling — the principle describes the pattern; tooling is project-specific (cog's lives
    in `repo-update-tracking`).

## Current State

### Key Files (resolve `$DOCS_NOTES_REPO` first)

- `$DOCS_NOTES_REPO/tech/programming/docs-design/` — existing files: `00-overview.md`,
  `01-diataxis-zones.md`, `02-lean-adrs.md`, `03-comments-and-code-as-sot.md`,
  `04-single-source-of-truth.md`, `05-drafts-and-promotion.md`, `06-operational-docs.md`,
  `07-ai-agent-considerations.md`, `99-checklist.md`, `AGENTS.md`, `README.md`, `template-adr.md`.
- `$DOCS_NOTES_REPO/tech/programming/docs-design/04-single-source-of-truth.md` — the SoT principle;
  the new principle references it (a tracked artifact is the SoT for a perishable fact; tracking keeps
  that SoT honest over time).
- `$DOCS_NOTES_REPO/tech/programming/docs-design/07-ai-agent-considerations.md` — AI-agent guidance;
  the new principle's "agents sweep and flag" framing should be consistent with it.
- `$DOCS_NOTES_REPO/tech/programming/docs-design/AGENTS.md` — digest with a `last-synced` date to bump.
- `$DOCS_NOTES_REPO/tech/programming/docs-design/README.md` — index/how-to-use; add the new file.

### Existing Patterns

- Each principle file is a focused, numbered markdown doc with a clear pattern statement, when-to-use,
  and examples. Match that voice and length (lean, not exhaustive).
- `AGENTS.md` is a digest of the shelf with a last-synced date (the shelf's own tracking discipline —
  fittingly, an instance of this very principle).
- Fenced code blocks need a language.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: tracking-file-doc-design-principle`)
`status` to `doing`.

### Step 0: Resolve and validate the target repo

Resolve `$DOCS_NOTES_REPO` (expected `/home/gbasso/DocsNNotes`). If unset or the docs-design shelf is
absent, stop with a clear message — the principle cannot be written without the shelf. Confirm the
next free principle number (expected `08`).

### Step 1: Write the principle file

Create `…/docs-design/08-tracking-and-revalidation.md` (use the next free number). Cover:

- **The pattern:** a *tracking file* is a machine-readable registry of perishable artifacts. Each
  entry records `path`, `last_checked`, a cadence, *why it perishes*, *how to revalidate it*, and
  *what depends on it*.
- **Primary audience = coding agents:** an agent sweeping the repo runs a scan over the tracking file,
  flags overdue entries, and either revalidates them or surfaces them; humans benefit too.
- **When to use it:** any repo/docs set holding facts that drift (benchmarks, pricing, model/tool
  rosters, external API shapes, security advisories). When *not* to: stable conceptual docs.
- **Relationship to SoT (`04`):** the tracked artifact is the SoT for its fact; tracking is the
  mechanism that keeps that SoT from going stale. Cross-link `[[04-single-source-of-truth]]`-style per
  shelf convention.
- **Cadence + revalidation workflow:** scan → pick overdue → re-research from authoritative sources →
  update the artifact (+ its "data collected" date) → bump the entry's `last_checked`.
- **Worked example:** the `cog` instance — `docs/reference/maintenance-tracking.yaml` consumed by a
  deterministic `cog tracking-scan` command — and the principle that the *scan/overdue computation*
  is deterministic tooling while *revalidation* is judgment.
- **Minimal schema sketch** (language-tagged fenced block) an adopting project can copy.

### Step 2: Update the shelf index, digest, and checklist

- `README.md`: add the new principle to the index/contents.
- `AGENTS.md`: add a one-line digest entry for the principle and bump the `last-synced` date to the
  execution date.
- `99-checklist.md`: add a review check, e.g. "Do any perishable facts in this change belong in a
  tracking file / have an up-to-date `last_checked`?"

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: tracking-file-doc-design-principle`)
   `status` to `done`.
2. All rounds are now done, so in the top-level `.implementation-plans/queue-plans.yaml` set this
   plan's (`item: docs-design-tracking-principle`) `status` to `done`. Leave the plan directory in
   place.

## Acceptance Criteria

- [ ] `$DOCS_NOTES_REPO/tech/programming/docs-design/08-tracking-and-revalidation.md` (or next free
      number) exists, states the pattern, audience, when-to-use, SoT relationship, cadence/workflow,
      the cog worked example, and a copyable schema sketch.
- [ ] `README.md` index, `AGENTS.md` digest (with bumped last-synced date), and `99-checklist.md` are
      updated.
- [ ] All fenced code blocks declare a language; the file matches the shelf's lean voice.
- [ ] No change was made to the `cog` repo source tree (only `$DOCS_NOTES_REPO` and this plan's
      `.implementation-plans/` metadata).
- [ ] This plan's `queue-rounds.yaml` shows the round as `done`, and the top-level
      `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

This is the final round.
