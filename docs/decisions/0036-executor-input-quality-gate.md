# ADR-0036: Executor input-quality gate

## Context and Problem Statement

Executors routed on a syntactic check only: `cog executor classify-input` called a readable `.md` path a "plan" and everything else a "prompt", skipping plan generation for `.md` input. A thin `.md` was treated as finished and a richly-detailed inline prompt was treated as needing a plan. Executors could not guarantee a good plan before executing, and multiple executors needed the same "is this input good enough?" judgment.

## Considered Options

- Keep syntactic routing; document the limitation.
- Add a quality judgment inline in each executor's prose.
- Add a canonical `assess-input` verdict skill the executors delegate to, plus a gated executor flow.

## Decision Outcome

Chosen option: **canonical verdict skill + gated flow** — one shared judgment, reused, auditable.

- A new `assess-input` twin skill (`other`-class, no governed marker) classifies input into a route `needs-plan` or `good-input` using the rubric in `skill-refs/orchestration/input-quality-rubric.md`. Deterministic signals and verdict persistence are `cog assess-input facts|record|validate` (`cog.assess-input.v1`).
- Both executors share one gated 2-phase flow `[prepare, execution]`. The prepare producer is route-dependent: `executor-oneshot` generates with `/plan-oneshot` or reviews with `/review-plan-oneshot` (run cross-engine for reviewer independence); `executor-vetted` generates with `/plan-multi` or multi-reviews with `/review-plan-multi`. `cog executor prepare-step` resolves the producer, engine, and lane; `cog executor adopt-prepared` normalizes a producer artifact into `prepared-plan.md`; the summary is `cog.executor.summary.v3` keyed on the route.
- `executor-vetted` is Claude-only — its multi producers run Claude and Codex together — so its Codex twin and `-codex` launcher are removed.

This refines the flow-descriptor model of [ADR-0028](./0028-executor-stage-phase-decoupling.md), superseding its per-executor flow definitions and the v2 summary schema while keeping its descriptor mechanism. The route honors [ADR-0008](./0008-skill-script-boundary.md) (judgment in the skill, mechanics in cog) and [ADR-0025](./0025-sot-executor-delegation.md) (shared judgment as a canonical skill).

## Consequences

- Good: every executor guarantees a vetted plan; the verdict is one tunable source of truth.
- Good: input quality, not file extension, drives generate-vs-review.
- Bad: the v2 init/summary schema and the removed vetted twins are breaking changes for in-lockstep consumers.

## Status

Accepted
