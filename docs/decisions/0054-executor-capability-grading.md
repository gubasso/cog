# ADR-0054: Executor capability grading and complexity matching

## Context and Problem Statement

The complexity rubric ([ADR-0049](./0049-plan-complexity-rubric.md)) grades a round's intrinsic difficulty but is deliberately executor-independent, and the power-grade matrix ([ADR-0032](./0032-power-grade-model.md)) grades model/effort cells. Nothing connected the two, so a round was routed to an executor by hand. The result is the waste ADR-0049 named from the other side: trivial rounds run through a full `executor-prex` cycle (wasted tokens/quota) and large rounds handed to a thin executor (leaked bugs). We need a deterministic, evidence-backed way to grade each executor's capability and match a complexity score to the right-sized executor. The existing `cog power-grade compound` is unusable for this: its `min(scale.max, max_pass + gain·(n−1))` formula saturates every multi-pass executor to 10, so it cannot rank them.

## Considered Options

- Hand-author a complexity→1–10 crosswalk and a per-executor grade table.
- Reuse `cog power-grade compound` as the executor metric.
- Derive executor power as the **sum** of its passes' matrix-cell grades and match by a **normalized-percentage overlay** of executor power bands onto the complexity ladder; persist only the pass composition and calibration constants, derive every number at runtime.

## Decision Outcome

Chosen option: **sum-of-passes power + normalized-% overlay, derived at runtime.**

- **Capability metric.** An executor's power is the sum of its stage powers along its heaviest route. A stage folds its passes by mode: `single` (the lone grade), `sum` (concurrent dual-engine passes, or sequential multi-round passes), or `max` (route-alternatives where only one path runs — grade the heaviest). Each pass maps to a matrix cell graded by its declared frontmatter where it has one, by its driven effort (Codex `run-exec`/inline `plan-oneshot`) otherwise, and by the model-tiers medium rung when neither applies. This yields `executor-oneshot 20 / executor-vetted 28 / executor-prex 52`.
- **Matching.** Normalize executor powers to a percent of the strongest executor (contiguous bands, previous ceiling = next floor) and normalize a complexity score to a percent of `complexity_max_score` (34), then overlay: a score routes to the executor whose band contains its percent. Scores above the extreme cutoff (`> 30`, ≈88.2%) are reserved — non-executable as a single round unless explicitly requested; `plan-builder-to-queue` routes each reserved round back through `plan-split` ([ADR-0056](./0056-plan-round-executor-routing-contract.md)).
- **Persist inputs, derive numbers.** `data/power-grade/executor-capability/passes.yaml` (the pass composition) and `calibration.yaml` (aggregation rule, `complexity_max_score` + provenance, the extreme cutoff) are the only persisted artifacts. Powers, %-bands, routing thresholds, and a round's executor choice are all derived at runtime by `cog power-grade executor` / `cog power-grade match` and never cached, so a matrix grade, pass, or rubric change cannot leave a stale number behind. This follows the `data/` is SoT + `cog` derives model ([ADR-0052](./0052-cog-data-directory-and-format.md)).

The numbers are a calibratable v1 heuristic, refit against git-history outcomes on the same discipline as the rubric weights. This supersedes the hand-built crosswalk idea: the 1–10 matrix grades feed the power sums, and matching is the dual-% overlay.

### Drift review triggers

Drift is caught strongest-first: the `cog power-grade executor-validate` machine guard (completeness — every native `executor-*` skill, excluding `-codex` delegation launchers per [ADR-0021](./0021-twin-skill-naming-and-delegation-hints.md), has a `passes.yaml` entry; referential integrity — every cell resolves in the matrix; calibration coherence — bands contiguous and cover the top, the extreme cutoff's score and percent agree), the `executor-capability` entry in `data/maintenance-tracking.yaml`, and this table:

| Change                                             | Auto-re-derives?                | Review trigger                                                                       |
| -------------------------------------------------- | ------------------------------- | ------------------------------------------------------------------------------------ |
| new `executor-*` skill                             | no                              | `executor-validate` **fails** until `passes.yaml` gains an entry                     |
| an executor's flow / a pass's model-effort changes | no                              | re-author `passes.yaml` (the entry references the skill; cadence + this ADR)         |
| matrix grade re-evaluation (`model-cells.yaml`)    | **yes** (powers + thresholds)   | re-validate calibration vs git history (tracking cross-ref on `power-grade-matrix`)  |
| rubric refit (weights / max / bins)                | partly                          | update `calibration.yaml` `complexity_max_score`                                     |
| `model-tiers` medium-default changes               | **yes** (medium-default passes) | `passes.yaml` records `basis: medium-default` per pass so the dependency is explicit |

## Consequences

- Good: deterministic, uncapped, and discriminating (20/28/52); the persist-inputs/derive-numbers split means a single source change re-derives everywhere with no stale cache.
- Good: matching is one overlay, not a hand-maintained crosswalk; `executor-validate` makes adding an executor without grading it a hard failure.
- Bad: bands and the extreme cutoff are opinionated until calibrated against git-history ground truth.
- Bad: `complexity_max_score` agreement with the rubric is asserted only as an internal constant — the rubric's max is still prose, so a machine cross-check waits until it is itself data (Finding 5).
- Bad: pass grades reflect declared/driven intent, not guaranteed runtime model — Claude subagent passes inherit the session model; closing that runtime-inheritance gap is a separate follow-up.

## Status

Accepted. Implemented: `data/power-grade/executor-capability/{passes,calibration}.yaml`, the `cog power-grade executor` / `match` / `executor-validate` surfaces, the `executor-capability` maintenance-tracking entry, and integration tests. The match→queue routing and the reserved-round split are wired by [ADR-0056](./0056-plan-round-executor-routing-contract.md) (`plan-builder-to-queue` / `plan-split`); the calibration follow-up is built by [ADR-0058](./0058-match-outcome-telemetry-and-calibration-loop.md) (match-outcome telemetry + cog-scoped, human-gated refit cadence). Remaining follow-up: make the rubric max machine-readable.
