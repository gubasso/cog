# Match-outcome telemetry

`cog match-telemetry` is the collector + analyzer for the plan→executor calibration loop ([ADR-0058](../decisions/0058-match-outcome-telemetry-and-calibration-loop.md)). It records whether each round's complexity→executor match ([ADR-0054](../decisions/0054-executor-capability-grading.md), [ADR-0056](../decisions/0056-plan-round-executor-routing-contract.md)) was right in practice, so the rubric weights and executor bands can be refit against real outcomes — by a human, in the cog repo.

## Store

One **append-only JSONL** stream, **always global**, independent of plan-store mode, so every cog instance on the machine shares one calibration corpus:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/cog/telemetry/match-outcomes.jsonl
```

`COG_TELEMETRY_ROOT` overrides the directory (tests). Writes are advisory-locked (`flock` when available) so concurrent cog instances across projects never interleave-corrupt a line. Every record is stamped with its `project_key` for provenance.

## Record kinds

Two kinds, joined by `project_key + plan_slug + round_id`:

- **prediction** (`cog.match-telemetry.prediction.v1`) — written by the plan producer at match time: `predicted_executor`, `score`, `grade`, `requirement_ids`.
- **outcome** (`cog.match-telemetry.outcome.v1`) — written by each `executor-*` skill at run terminus: `actual_executor`, `result` (`pass|fail`), `reverted`, `retries`, `loc_changed`, `files`, plus a per-executor **marginal-value** field and an optional `note` attached only when signals conflict. Marginal-value fields are omitted when not applicable:
  - `executor-prex` → `review_loop_findings` (relevant findings across the review loop).
  - `executor-vetted` → `cross_engine_deltas` (distinct corrections the second engine contributed).
  - `executor-oneshot` (+ `-codex` twin) → floor; neither headroom field.

## Verbs

```text
cog match-telemetry record --kind prediction --project-key <k> --plan-slug <s> --round-id <r> \
  [--requirement-ids <csv>] --predicted-executor <e> --score <n> [--grade <g>] --json
cog match-telemetry record --kind outcome --project-key <k> --plan-slug <s> --round-id <r> \
  --actual-executor <e> --result <pass|fail> [--reverted] [--retries <n>] [--loc-changed <n>] \
  [--files <n>] [--review-loop-findings <n>] [--cross-engine-deltas <n>] [--note <text>] --json
cog match-telemetry round-key --round-path <abs> [--project-root <dir>] --json
cog match-telemetry path --json
cog match-telemetry validate [--file <path>] --json
cog match-telemetry report [--project-key <k>] [--since <YYYY-MM-DD>] [--file <path>] --json
```

`round-key` resolves `{project_key, plan_slug, round_id, requirement_ids}` from a queued round file so executor skills record without parsing (producer-blind).

## Verdict rules

`report` joins each outcome to its prediction and labels the round, deterministically — it never edits grades:

- **under-powered** — `result == fail`, `reverted == true`, or `retries >= 2`.
- **over-powered** — zero marginal value on a headroom-bearing executor (`review_loop_findings == 0` for prex, `cross_engine_deltas == 0` for vetted) with no failure signal.
- **well-matched** — otherwise.
- **needs_review** — no matching prediction, or `predicted_executor != actual_executor`.

The refit decision is human-gated by the `match-telemetry-calibration` entry in `data/maintenance-tracking.yaml`, surfaced on `cog tracking-scan`.

## Calibration review log

The telemetry stream is the raw evidence corpus; it does not record the human's verdict. Each `report`-based review appends one entry to the decision journal at `data/power-grade/executor-capability/calibration-reviews.yaml` — a hand-maintained YAML with a `schema_version` and a `reviews:` list, so the _what/when/why_ of every calibration decision accumulates over time. A review entry is self-contained:

- `date`, `reviewer`, and `scope` (`project_key` + `plan_slug` reviewed).
- `corpus` and `rollup` — the report's counts and verdict tallies at review time.
- `rounds` — the per-round `score`/`grade`/`executor`/`result`/`marginal_value`/`quality` reviewed.
- `decision` (`no-refit` or a description of the applied refit) and a prose `rationale`.
- `report_snapshot` — path to the frozen `cog match-telemetry report --json` output for this cycle, committed under `data/power-grade/executor-capability/calibration-reports/<date>-<scope>.json` as byte-exact evidence.

A review cycle is: run `report`, append a `reviews:` entry, freeze the report JSON snapshot, apply a refit by hand only if warranted, then bump the entry's `last_checked` in `data/maintenance-tracking.yaml`. The journal is not read by the CLI — it is the durable human-decision history beside the machine corpus.
