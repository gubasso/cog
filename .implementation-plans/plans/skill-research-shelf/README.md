# Skill research shelf: a tracked, reusable in-repo research store

> Complexity: M | Rounds: 3 | Generated: 2026-06-19 | Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Problem Statement

The new plan/review-plan/executor skills each need deep web research (official Claude Code and Codex
CLI/skills specs; best-practice plan, plan-review, and single-agent-executor patterns). The user's
directive: do the research ONCE, persist it in a tracked, reusable in-repo location, and reuse it
across calls "so one research can help the other." Without a shelf, each new skill would re-research
ad hoc and the findings would not be tracked for revalidation.

This plan builds that shelf: a deterministic `cog` command family that owns the shelf mechanics, the
persisted dated findings under `docs/reference/`, and registration into the repository's
periodic-revalidation tracking registry. It mirrors the dated-evidence precedent already set by
`model-effort-policy-and-rename` (which persisted model-reference research in `docs/reference/`).

## Strategy

Three dependency-ordered rounds: build the store, then populate it from official sources, then add
best-practice findings and register it for tracking.

1. `research-shelf-cog-command` — the deterministic `cog research-shelf` command family + schema.
2. `official-docs-research` — the dedicated web-research pass over official Claude Code / Codex specs,
   persisted to the shelf.
3. `best-practice-research-and-tracking` — best-practice plan/review/executor patterns + register the
   shelf in the tracking registry.

## Rounds

1. `research-shelf-cog-command.md` — `cog research-shelf` (init/record/list/get/validate) + schema + bats.
2. `official-docs-research.md` — official Claude Code + Codex CLI/skills research, persisted.
3. `best-practice-research-and-tracking.md` — best-practice patterns + tracking-registry entry.

## Execution Commands

```bash
# Execute the next todo round:
/prex -ar @.implementation-plans/plans/skill-research-shelf/

# Or target a specific round file directly:
/prex -ar .implementation-plans/plans/skill-research-shelf/research-shelf-cog-command.md
```

## Execution Discipline

Rounds are executed one at a time, one `/prex` session per round. `/prex` reads this plan's
`queue-rounds.yaml`, runs the first `todo` round, flips it `done`, and stops. Commit each round with
`/gc -a` afterward.

## Decisions & Constraints

- `Executor: prex (EF 1.5)`.
- Findings are persisted as dated lookup material under `docs/reference/` (Diátaxis reference) — NOT
  inlined into skill bodies. Skills read the shelf and `cog research-shelf` summaries; they cite the
  shelf, never raw URLs in their prose.
- All shelf mechanics (paths, ids, dating, validation, index) are deterministic `cog` commands; the
  judgment (what to search, what to record) stays in the round/skill prose.
- "Tracked" reuses the existing `repo-update-tracking` registry
  (`docs/reference/maintenance-tracking.yaml` + `cog tracking-scan`) — this plan REGISTERS an entry,
  it does not build a new tracking engine.
- Markdown fences declare a language. Do not run git commands inside round bodies.

## Reconciliation (depends_on, no duplication)

- `depends_on: repo-update-tracking, docs-design-tracking-principle` — the periodic-revalidation
  registry + the tracking-file docs-design principle are owned there; this plan registers the shelf
  into that registry rather than reimplementing tracking.
- `depends_on: model-effort-policy-and-rename` (done) — reuses its dated-evidence-in-`docs/reference/`
  precedent and format.
- Consumed by `lean-plan-and-review-skills` and `executor-single-agent-wrappers`, which read the shelf
  instead of doing their own ad-hoc research (one research helps the others).
