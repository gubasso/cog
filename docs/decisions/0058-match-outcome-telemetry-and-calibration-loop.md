# ADR-0058: Match-outcome telemetry and calibration loop

## Context and Problem Statement

`cog power-grade match` ([ADR-0054](./0054-executor-capability-grading.md)) routes a score to an executor, but nothing measures whether the match was right in practice; both [ADR-0049](./0049-plan-complexity-rubric.md) and ADR-0054 deferred the feedback arm, so the rubric weights and executor bands stay uncalibrated against real outcomes.

## Considered Options

- A mandatory per-run operator rating (high friction; excludes silent/automated runs).
- A telemetry stream inside the plan-vault root (fragments the corpus when a project uses a local store).
- A cross-project, append-only telemetry stream + a cog-scoped, human-gated analyzer; never auto-refit grades.

## Decision Outcome

Chosen option: **cross-project append-only telemetry + cog-scoped human-gated analyzer.**

- **Collector (cross-project, always global).** One append-only JSONL stream at `${XDG_DATA_HOME:-$HOME/.local/share}/cog/telemetry/match-outcomes.jsonl` (the `data/research-shelf/index.jsonl` precedent), independent of plan-store mode and stamped with each record's `project_key`. Two record kinds joined by `project_key + plan_slug + round_id`: a **prediction** written at plan-build time (predicted executor, score, grade, requirement IDs), and a per-executor **marginal-value outcome** at run terminus — `executor-prex` review-loop relevant- findings, `executor-vetted` cross-engine deltas, `executor-oneshot` floor (no headroom field) — with objective metrics (LOC/files/retries/result/reverted) and a note attached **only** when signals conflict. Writes are concurrency-safe so any cog instance can append.
- **Analyzer (cog-scoped, human-gated).** `cog match-telemetry report` deterministically joins prediction↔outcome into per-round `well-matched | over-powered | under-powered` verdicts (over-power = zero marginal value on the top rung; under-power = fail/revert/high-retries), flagging conflicting rows `needs_review`. A `match-telemetry-calibration` entry in `data/maintenance-tracking.yaml` surfaces the refit decision on `cog tracking-scan`. The report **only aggregates and surfaces — it never auto-mutates grades** ([ADR-0008](./0008-skill-script-boundary.md)).

## Consequences

- Good: closes the calibration arm both ADR-0049 and ADR-0054 deferred; one cross-project corpus; objective-first so automated runs still contribute.
- Bad: verdict fidelity rests on the marginal-value checkpoints; a noisy single run is mitigated by cross-run aggregation + `needs_review` and the human-gated refit.

## Status

Accepted.

Will flip to Implemented with links to [cmd_match_telemetry.sh](../../lib/commands/cmd_match_telemetry.sh) and [fn_match_telemetry.sh](../../lib/functions/fn_match_telemetry.sh) once the telemetry tests pass.
