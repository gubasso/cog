# Repo Update-Tracking: A Periodic-Revalidation Registry + `cog tracking-scan`

> Complexity: M | Rounds: 2 | Generated: 2026-06-19 | Repo: /workspaces/cog

## Problem Statement

Some facts in a repository are **perishable**: they were true and well-sourced when written, but
drift over time and must be periodically re-researched and revalidated. The clearest example here is
the model/effort evidence produced by the `model-effort-policy-and-rename` plan
(`docs/reference/models-reference-claude.md` and `…-codex.md`): benchmarks, pricing, and available
models change, and the policy that rests on them is only as good as its last revalidation. The
existing DocsNNotes copies already drifted (Opus 4.7 vs 4.8) precisely because nothing tracked them.

Today nothing in `cog` records *which* artifacts need periodic revalidation, *how often*, *how* to
revalidate them, and *what else depends on them*. A coding agent sweeping the codebase has no
machine-readable signal telling it "this reference is overdue — go re-research it."

This plan adds a **tracking registry** (a structured, descriptive data file listing perishable
artifacts with a cadence and a revalidation procedure) and a deterministic `cog tracking-scan`
command that reports overdue entries — so an agent sweeping the repo (or a human, or CI) can flag
stale references and trigger a refresh. It is the in-repo, concrete instance of the general
"tracking-file / periodic-revalidation" docs-design principle authored by the sibling plan
`docs-design-tracking-principle`.

## Strategy

Two dependency-ordered rounds. Round 1 defines the registry data format and runbook and seeds it with
the model-data entries. Round 2 adds the deterministic `cog tracking-scan` command (per the
skill/script boundary, the mechanical "is this overdue?" check belongs in `cog`, not in prose) and
wires a sweep cue into `AGENTS.md`.

## Rounds

1. `tracking-registry.md` — the descriptive tracking data file + its runbook, seeded with the model/effort reference entries.
2. `tracking-sweep-tooling.md` — `cog tracking-scan` command (reports overdue entries) + tests + completion/man + an AGENTS.md sweep cue.

## Execution Commands

```bash
# Execute the next todo round (executor reads queue-rounds.yaml, runs the first todo round, then stops):
/prex -ar @.implementation-plans/plans/repo-update-tracking/

# Or target a specific round file directly:
/prex -ar .implementation-plans/plans/repo-update-tracking/tracking-registry.md
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for
a single `/prex` session. Do not implement multiple rounds in one session.

When `/prex` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh `/prex` session is launched for any subsequent round.

## Decisions & Constraints

- `Executor: prex (EF 1.5)`.
- **Dependencies:** `depends_on model-effort-policy-and-rename` (it produces the first tracked
  artifacts) and `docs-design-tracking-principle` (it defines the general pattern this plan
  instantiates). If the docs-design principle is not yet authored, this plan still proceeds but
  should mirror its intended shape.
- **Deterministic mechanic in `cog`:** the "is an entry overdue?" computation is deterministic and
  belongs in a `cog` subcommand (`cog tracking-scan`), not in skill prose — per the skill/script
  boundary (`docs/decisions/0008-skill-script-boundary.md`).
- **Registry format = YAML** with descriptive fields, consistent with the repo's other YAML data
  (`.implementation-plans/queue-*.yaml`) and trivially parseable by `cog`.
- **Date handling:** `cog tracking-scan` compares `last_checked + cadence` against "today". Since the
  command needs the current date, it reads it from the system clock at run time (this is a CLI
  command, not a plan-writer script); document the date source.

## Rejected Alternatives

- **A prose "things to revalidate" checklist in a doc.** Rejected: not machine-readable, no overdue
  computation, easy to ignore during a sweep.
- **Encoding cadence only inside each reference file's `Revalidate by:` line.** Kept as a
  human-facing hint, but the registry is the single queryable index so a sweep does not have to crawl
  every file.

## Risks & Edge Cases

- **Registry drift from reality** (an artifact is revalidated but its `last_checked` not bumped).
  Mitigated by making the revalidation runbook end with "update the registry entry", and by
  `cog tracking-scan` being cheap to run in CI.
- **Date source determinism.** `cog tracking-scan` uses the real clock; tests must inject a fixed
  "now" (e.g. via a `--now <date>` flag or env) to stay deterministic.

## Completion

When all rounds are done, set each round `done` in this plan's `queue-rounds.yaml` and set this plan
`done` in the top-level `.implementation-plans/queue-plans.yaml`. Nothing moves on disk.
