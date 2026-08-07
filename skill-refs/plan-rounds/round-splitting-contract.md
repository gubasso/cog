# Round-Splitting Orchestration Contract

The contract for turning an a-priori complexity grade into a right-sized set of rounds: the _largest_ rounds that each grade at or below the single-session ceiling. Work is consolidated into one round, then split only when forced, recursively, until every round fits. This file is the single source of truth for the split loop; skills that implement the roles point here and do not restate the schemas, the dispatch table, or the ceiling policy.

Grading itself is defined in `complexity-rubric.md` (this directory); resolve both with `cog skill-refs path plan-rounds/<file>`. The decision and its rationale are [ADR-0013](../../docs/decisions/ADR-0013-complexity-driven-round-sizing.md).

## The three roles

| Role             | Prefix             | Nature                         | Owns                                                                                          |
| ---------------- | ------------------ | ------------------------------ | --------------------------------------------------------------------------------------------- |
| **Evaluator**    | `review-plan-*`    | pure, read-only, parallel-safe | one plan/round → a complexity report per the rubric, including the split signal               |
| **Splitter**     | `plan-*`           | generative judgment            | one over-ceiling round + seam hints → exactly two complete, information-preserving rounds     |
| **Orchestrator** | `plan-*` (+ `cog`) | deterministic control flow     | the queue, the parallel fan-out, the threshold compare, the recursion, the termination guards |

The evaluator is blind to whether its input is a whole plan, one round, or a post-split fragment — it grades whatever prose it is given. The splitter is the only writer. The orchestrator never analyzes.

## The serialized-judgment boundary

The split decision is _not_ split into "whether (deterministic) vs. how (judgment)." Every analytic call — the grade, is-it-splittable, where-to-cut, did-the-split-reduce — is made by a worker and rendered into structured fields. The orchestrator's decision is then a pure dispatch over those fields plus one constant compare. Judgment never leaves the workers; it arrives at the orchestrator as data. This is the skill/script boundary ([ADR-0007]) over the machine-output contract ([ADR-0003]).

[ADR-0007]: ../../docs/decisions/ADR-0007-skill-and-cli-responsibility-boundary.md
[ADR-0003]: ../../docs/decisions/ADR-0003-machine-facing-output-contract.md

## Contracts

### Evaluator

Input: one plan directory `README.md`, one round file, or a queue — prose, graded a priori.

Output: the complexity report defined by `complexity-rubric.md`, which carries the grade, the seven-axis vector, the drivers, and the split signal:

```yaml
grade: Extreme
score: 30.6
axis_scores: { scope: 4, breadth: 4, coupling: 4, novelty: 3, behavior: 3, verification: 4, context: 3 }
drivers:
  - changes a public CLI contract and migrates its persisted schema
  - broad feature set spanning several workflows and subsystems
  - requires integration, migration, and rollback verification
splittable: true                 # false => an irreducible atom; no acceptable seam exists
seam_hints:                       # advisory candidate cuts, weakest connascence first
  - label: contract-vs-docs
    connascence: low
    left:
      label: contract-and-schema
      requirement_ids: [R1, R2, R3]
    right:
      label: docs-and-completion
      requirement_ids: [R4, R5]
```

The evaluator is pure: same input, same report. It names seams; it never makes the cut.

### Splitter

Input: one round whose grade exceeds the ceiling, plus that round's `seam_hints`.

Output: a verdict. It cuts at the lowest-connascence seam, preserves every requirement on both sides, and names each child for its cohesive content — never an ordinal, per [ADR-0017]:

```yaml
split_performed: true            # false => the splitter judged the round irreducible
seam:
  between: [ contract + schema migration, docs/completion/help updates ]
  connascence: low
rounds:
  - id: contract-and-schema-migration
    path: .implementation-plans/plans/<plan>/contract-and-schema-migration.md
  - id: docs-and-completion-updates
    path: .implementation-plans/plans/<plan>/docs-and-completion-updates.md
coverage:
  key: id
  parent_reqs: [R1, R2, R3, R4, R5]
  lost: []                       # must be empty — a lossy split is rejected
  added: [R6]
  duplicated: [R3]               # informational; a shared foundation may intentionally recur
```

[ADR-0017]: ../../docs/decisions/ADR-0017-skill-authoring-and-lint.md

### Requirement identity

Acceptance criteria may carry a leading plan-scoped requirement tag:

```text
- [ ] (R3) The command fails closed when coverage loses a parent requirement.
```

The requirement tag is the parenthesized `(R<n>)` form on an acceptance-criteria bullet. It is a distinct textual form from a content-named round identifier (the `id` field) and from bare `R<n>` round references or `### Round N` headings, so those never collide with requirement-tag parsing.

`cog round-req stamp <round-or-plan-path>` owns allocation. It scans the plan directory for the current max, assigns monotonic `R1`, `R2`, ... tags to untagged non-boilerplate acceptance criteria, and never renumbers existing tags. Directory targets stamp every round file in the plan directory, skipping README, STRATEGY, and queue files. File targets stamp only that file while scanning sibling round files for the current max.

Ownership is split:

- callers stamp before grading so seams and coverage can use stable IDs end to end;
- the splitter defensively stamps the parent and child files idempotently;
- the evaluator stays read-only and reports whether requirements were already stamped.

Coverage keys on IDs when present and falls back to normalized criterion text for legacy untagged rounds. `cog round-split coverage` fails closed when any parent requirement is lost. Duplicate or malformed IDs are invalid within one input scope. A shared parent ID may recur across children and is reported as duplicated.

The two Template-A bookkeeping criteria for queue completion are excluded from stamping, listing, and coverage. The queue-round criterion is matched by normalized pattern because its topic token varies; the final-plan criterion is matched by normalized exact text.

### Orchestrator dispatch

`cog round-rightsize` switches on the two worker verdicts plus one internal ceiling compare; the orchestrating skill only relays the verdicts. No branch contains analysis. This dispatch table is the behavioral spec of cog's `record-grade`/`record-split` verbs:

```text
report := evaluate(round)                                  # review-plan-* worker, fanned out
over   := cog plan-complexity over-ceiling --grade <report.grade>

not over                          -> final.append(round)                  # largest-that-fits, keep it
over and not report.splittable    -> final.append(round); flag irreducible-over-ceiling
over and report.splittable        -> verdict := split(round, report.seam_hints)   # plan-* worker

# resolve the splitter's ground truth:
verdict.split_performed == false  -> final.append(round); flag irreducible-over-ceiling
verdict.split_performed == true   -> cog round-split coverage --parent <round> --children <verdict.rounds>
                                     queue.extend(verdict.rounds)          # re-graded next pass
```

`splittable` is the evaluator's prediction; `split_performed` is the splitter's fact. A wrong prediction collapses into the same terminal flag, so the queue always converges.

## The loop

```text
queue    := [ consolidated single max-size round ]         # start largest, per the maximize-size goal
baseline := evaluate(queue[0])                             # "everything as one" — kept for conservation
final    := []
while queue not empty:
    batch   := drain(queue)
    reports := parallel( evaluate(r) for r in batch )       # one read-only evaluator per round
    for (r, report) in zip(batch, reports):
        dispatch(r, report)                                 # appends to final, or enqueues children
assert cog round-split coverage --parent baseline --children <final>   # union still covers the origin
return final                                                # every round graded, all at/under ceiling
```

Each pass grades all un-evaluated rounds in parallel, keeps the ones that fit, and replaces each over-ceiling round with its two children. The recursion bottoms out when every round is at or below the ceiling or flagged irreducible. Because every child is re-graded, an unbalanced intermediate self-corrects and a natural three-way split is reached over two passes.

This loop is implemented by the `cog round-rightsize` state machine ([ADR-0013]): `init` seeds the single parent round; `pending` drains a pass into its two parallel buckets; `record-grade` runs the ceiling compare; `record-split` runs coverage and enqueues the two children; `finalize` asserts the baseline conservation. The orchestrating skill advances it step by step and supplies only worker judgment; it never mutates the queue.

[ADR-0013]: ../../docs/decisions/ADR-0013-complexity-driven-round-sizing.md

## Ceiling policy

The ceiling is the rubric bin above which a round must split: the largest grade a single execution session reliably holds. It is **executor-independent** — a property of "one cohesive unit of work," not of any executor's capacity. Coupling it to an executor would re-entangle complexity with capability, the conflation [ADR-0013] removed.

It is a single calibratable constant resolved by `cog plan-complexity ceiling`, defaulting to **Very High** and optionally overridden for a process with the `COG_PLAN_COMPLEXITY_CEILING` environment variable. It is intentionally env-only in this round; cog config files do not accept that key. Only rounds grading **Extreme** must split under the default. This is the conservative, size-maximizing default: a **Very High** round is deliberately kept as one large unit (the rubric's "unless a large round is deliberate" clause). The [ADR-0013] calibration loop tunes it against repo outcomes; nothing else hard-codes a bin.

## Invariants

- **Scope conservation.** A split redistributes scope (axis A); it never creates or destroys work. The union of the children covers the parent's requirements exactly — `coverage.lost` is empty. The final conservation check re-grades the union against the baseline.
- **Coupling and context reduction.** A split lowers each child's coupling (axis C) and context load (axis G) by cutting at the lowest-connascence seam. That reduction — not any change in total scope — is what pulls the grade under the ceiling, and it is the splitter's objective function.
- **Information preservation.** Both children are complete, standalone rounds. Detail is moved, never trimmed to fit a document boundary; a shared foundation (types, interfaces, config) may recur in both children and is reported in `coverage.duplicated`, not treated as loss.
- **Idempotent grading.** The evaluator is a pure function of its input prose, so re-grading a round — or the whole set as one — is free and repeatable.
- **Content-named children.** Child round identifiers are cohesive-content slugs, never split ordinals ([ADR-0017]).
- **Producer-blind dispatch.** The orchestrator depends on the report and verdict _schemas_, not on which skill produced them ([ADR-0017]).
- **Queue-blind splitting.** The splitter writes child rounds and a verdict only. The caller owns `queue-rounds.yaml` reconciliation, either after each loop or at the end.
- **Queue-mutation closure.** Only `cog round-rightsize record-split` appends rounds, and only after `round-split coverage` passes; the seed is always exactly one parent round. No verb accepts a list of rounds, and `init` rejects a baseline that already carries authored `### Round N` sections, so a caller cannot materialize many rounds up front ([ADR-0013]).

## Deterministic mechanics (cog surface)

The judgment lives in the three skills; the deterministic mechanics they call live in `cog`:

- `cog plan-complexity extract <plan>` — pre-score the rubric's mechanically extractable signals from plan text and a file graph; flag the axes that need a judgment pass.
- `cog plan-complexity ceiling` — resolve the single calibratable ceiling bin.
- `cog plan-complexity over-ceiling --grade <G>` — the deterministic compare; returns a boolean.
- `cog round-split coverage --parent <p> --children <a> <b>` — assert requirement/acceptance-criteria coverage of a split (and of the final union against the baseline); fail closed on any `lost` item.
- `cog round-req stamp <round-or-plan-path>` — idempotently assign plan-scoped requirement IDs.
- `cog round-req list <round>` — read requirement IDs and normalized criterion text.
- `cog round-rightsize <init|pending|record-grade|record-split|reopen|status|finalize>` — the loop state machine itself. cog owns the durable JSON work queue, the single-parent seed, the over-ceiling compare, the coverage-gated binary enqueue, termination, and the baseline conservation assertion.

The work queue is a durable JSON state file owned by `cog round-rightsize`, not orchestrator prose. The skill supplies only the grade and split verdicts; it cannot add a round except through a coverage-passing split, so no skill reimplements the loop in prose.

## Parallelism and isolation

- **Evaluators** are read-only and fan out freely — one per un-evaluated round, no worktree, no contention.
- **Splitters** within a pass each operate on a _disjoint_ over-ceiling round and write to disjoint content-slug paths the orchestrator assigns, so they parallelize without a worktree.
- Role `model`/`effort` tiers follow `docs/reference/model-effort-policy.md` and are registered per [ADR-0014](../../docs/decisions/ADR-0014-model-effort-and-power-grade.md) when the skills are built.

## Handoff to executor matching

The loop's output is the boundary: a converged set of rounds, each carrying a grade, all at or below the single-session ceiling, with the original work conserved. Matching each round's grade to an executor is a separate downstream scope (its own lookup, its own ADR) and is deliberately out of scope here — keeping the round set executor-independent is what lets it be re-graded or re-split without re-opening the match.
