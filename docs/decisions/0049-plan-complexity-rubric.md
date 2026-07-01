# ADR-0049: A-priori plan/round complexity rubric

## Context and Problem Statement

The complexity grade was set by a five-axis heuristic that divided a raw score by an Executor Factor
(EF) to pick `S/M/L/XL`. It conflated work complexity with executor capability (the EF), was
prose-only with no evidence base, and routinely mis-routed — trivial rounds graded `M` and run by a
heavyweight multi-pass executor, wasting capacity. We need an evidence-backed, executor-independent
way to grade a plan or round a priori, from its prose, that a `cog` command can partly extract and a
skill can refine.

## Considered Options

- Keep and patch the five-axis EF heuristic.
- Adopt a new seven-axis, evidence-backed, a-priori rubric; make complexity executor-independent and
  route by cross-matching the grade against the power-grade capability matrix.
- Defer until ground-truth run data exists.

## Decision Outcome

Chosen option: **adopt the seven-axis rubric** in `skill-refs/plan-rounds/complexity-rubric.md`
(scope, structural breadth, coupling/blast-radius, novelty/uncertainty, behavioral/cognitive,
verification cost, context load), scored `0–4`, weighted-summed with hard-escalation floors, a
clarity gate, and `Trivial→Extreme` bins. Complexity is intrinsic to the work and the EF mechanism is
dropped. Executor capability and grade→executor matching are separate concerns, out of scope here and
decided on their own. Each axis cites estimation, complexity, and agentic-coding literature; a
calibration loop refits the weights against repo outcomes. The deterministic/judgment split keeps
mechanical extraction in `cog` and nuanced reads in a skill, per
[ADR-0008](0008-skill-script-boundary.md). This retires the five-axis heuristic.

## Consequences

- Good: evidence-backed and executor-independent; the deterministic/judgment split lets `cog` extract
  reliable signals while a skill refines judgment; fixes the over-grading that wasted executor capacity.
- Good: one self-contained source of truth for sizing, grading, and splitting.
- Bad: weights and thresholds are opinionated until calibrated against git-history ground truth — the
  calibration loop is now built by [ADR-0058](0058-match-outcome-telemetry-and-calibration-loop.md)
  (match-outcome telemetry + a cog-scoped, human-gated refit cadence).

## Status

Implemented. The `cog plan-complexity` extractor exists and is tested; the consuming surfaces are the
`plan-*` producer ([ADR-0056](0056-plan-round-executor-routing-contract.md)) and the shared
`skill-refs/plan-rounds/*`; `skill-refs/plan-rounds/complexity-heuristic.md` is retired. The deferred
"refit rubric weights against outcomes" follow-up is addressed by
[ADR-0058](0058-match-outcome-telemetry-and-calibration-loop.md).
