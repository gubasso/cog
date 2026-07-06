# ADR-0050: Recursive complexity-driven round right-sizing

## Context and Problem Statement

[ADR-0049](0049-plan-complexity-rubric.md) grades a plan or round a priori but says nothing about
what to do with an over-large grade. The goal is the *largest* round that still executes reliably in
one session — one substantial prompt beats many thin ones — so the system consolidates work into a
single round, then splits only when forced, recursively, until every round fits.

That raises one architectural question: where does the *split* live? Grading is judgment (the
rubric); splitting is generative judgment; the loop that drives them is control flow. Folding
splitting into the grader destroys the three properties we want — parallel fan-out, bias-isolated
re-grading, and a single reusable measuring instrument — and a grader that mutates its input cannot be
run read-only over many rounds at once. Putting split *analysis* into the orchestrator re-imports
judgment into what must stay deterministic control flow.

## Considered Options

- **Evaluator splits.** The grading skill grades, then restructures the plan into rounds.
- **Orchestrator splits inline.** The loop reads the grade and itself analyzes where to cut.
- **Pure evaluator + dedicated splitter + deterministic orchestrator.** Three roles; every analytic
  call is serialized into structured report fields before the orchestrator dispatches on them.

## Decision Outcome

Chosen option: **three roles with a serialized-judgment boundary.**

- **Evaluator** (`review-plan-*`): pure, read-only, parallel-safe. One plan/round → a complexity
  report per the rubric, extended with `splittable` and `seam_hints`. Blind to whether its input is a
  whole plan, one round, or a post-split fragment.
- **Splitter** (`plan-*`): generative judgment. One over-ceiling round plus seam hints → exactly two
  complete, information-preserving rounds, cut at the lowest-connascence seam. Returns a verdict
  carrying `split_performed` — the ground truth for splittability.
- **Orchestrator** (`plan-*` plus `cog` predicates): deterministic control flow only. Owns the queue,
  the parallel fan-out, the threshold compare, the recursion, and the termination guards. It never
  analyzes; it switches on fields the workers already judged.

The boundary is not "whether (deterministic) vs. how (judgment)." Every analytic call — the grade,
is-it-splittable, where-to-cut, did-the-split-reduce — is made by a worker and rendered into
structured fields. The orchestrator's decision is then a pure dispatch over those fields plus one
constant compare, per [ADR-0008](0008-skill-script-boundary.md) and the machine-output contract
[ADR-0009](0009-machine-facing-output-contract.md).

Two correctness pins:

- **The split target is an executor-independent single-session ceiling.** The loop splits to the
  rubric's "one cohesive unit completable in a single execution session" bin, not to any executor's
  capacity. Targeting an executor would re-entangle complexity with capability — the exact conflation
  [ADR-0049](0049-plan-complexity-rubric.md) removed. Executor matching is a separate downstream
  scope, out of scope here.
- **Termination is guarded by worker ground truth.** A round terminates when its grade is at or below
  the ceiling, or when it is irreducible. `splittable` is the evaluator's *prediction*; the splitter's
  `split_performed: false` is the *fact*. The orchestrator absorbs a wrong prediction into a single
  terminal flag, so a queue cannot loop forever.

A good split conserves scope (axis A) but cuts coupling (axis C) and context load (axis G) — that is
*why* the grade falls below the ceiling, and it tells the splitter where to cut: the lowest-connascence
boundary. The same pure evaluator grades each round, the whole set as one, and every post-split child,
which yields the conservation re-grade for free. Child rounds are named for their cohesive content,
not split ordinals, per [ADR-0040](0040-stage-agnostic-identifiers.md). The full contract — schemas,
dispatch table, loop, ceiling policy, invariants, and `cog` surface — lives at
`skill-refs/plan-rounds/round-splitting-contract.md`.

## Consequences

- Good: evaluators fan out read-only with no contention; the grader is reusable and idempotent; no
  judgment leaks into the orchestrator; the loop greedily keeps the largest round that fits.
- Good: bias isolation — work is graded by an instrument that did not produce it, in the spirit of the
  best-constructed-input standard [ADR-0043](0043-best-constructed-input-standard.md).
- Good: producer-blind by construction — the orchestrator depends on the report schema, not on which
  skill emitted it, per [ADR-0026](0026-consumer-skill-producer-blindness.md).
- Bad: more moving parts than one skill — three roles plus `cog` predicates.
- Bad: the ceiling is a calibratable constant, defensible only against the
  [ADR-0049](0049-plan-complexity-rubric.md) calibration loop.
- Requires a follow-up implementation round: the `review-plan-*` evaluator, the `plan-*` splitter and
  orchestrator skills (or a mode of the existing multi-round plan emitter), and the `cog
  plan-complexity` / queue / coverage predicates.

## Status

Implemented. The deterministic `cog plan-complexity`, `cog round-req`, and `cog round-split` surface
exists; the Claude evaluator (`review-plan-complexity`) and splitter (`plan-split`) worker skills
exist; the requirement-ID spine, ID-based seam hints, queue-blind splitter contract, and coverage
semantics are registered in the shipped plan-round references. The orchestrator role is implemented by
`skills/claude/plan-builder-to-queue/`, with the loop control flow itself owned by the `cog
round-rightsize` state machine per [ADR-0069](0069-rightsize-loop-cog-state-machine.md); grade↔executor
matching is implemented by
[ADR-0056](0056-plan-round-executor-routing-contract.md) / [ADR-0054](0054-executor-capability-grading.md).
