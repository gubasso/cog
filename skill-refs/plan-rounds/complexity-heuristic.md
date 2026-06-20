# Complexity Heuristic & Round-Splitting Rules

Shared classification system for implementation plans. Determines the complexity grade and how to
split work into rounds.

## Five scoring axes

Evaluate the implementation surface along each axis (score 1–4):

| Axis                   | 1 (Low)           | 2 (Medium)        | 3 (High)            | 4 (Very High)     |
| ---------------------- | ----------------- | ----------------- | ------------------- | ----------------- |
| Files to change        | 1–3               | 4–8               | 9–15                | 16+               |
| Cross-cutting concerns | None              | 1 (e.g., logging) | 2–3                 | 4+                |
| Dependency chains      | Independent steps | Linear chain      | Diamond deps        | Complex DAG       |
| Pattern novelty        | All existing      | 1 new pattern     | 2–3 new patterns    | New architecture  |
| Risk / blast radius    | Isolated module   | Single subsystem  | Multiple subsystems | Core/shared infra |

## Executor profile

The grade thresholds below are calibrated against an **Executor Factor (EF)** that reflects what the
round-runner can absorb in one session. The default executor is `prex`, which runs four model passes
per round (Codex plan → Claude review → Codex implement → Claude review-loop with fixes). Because
the review-loop catches and fixes mid-round, a `prex` round can absorb meaningfully more raw
complexity than a single-shot model.

| Executor profile | EF  | When it applies                                                           |
| ---------------- | --- | ------------------------------------------------------------------------- |
| `prex` (default) | 1.5 | Codex plan + Codex implement + Claude review-loop. Default for this repo. |
| `single-pass`    | 1.0 | One capable model, no in-round review gate. Raw score stands.             |
| `limited`        | 0.8 | Weaker model or constrained context. Bumps complexity up.                 |

See `plan-lifecycle.md` § "Executor capacity model" for the prex pipeline details.

## Grade mapping

1. Sum the five axis scores → **raw score** (range 5–20).
2. Divide by the EF for the selected executor → **adjusted score**.
3. Map the adjusted score to a grade:

| Grade  | Adjusted  | Rounds      | Output format             | Notes                                                         |
| ------ | --------- | ----------- | ------------------------- | ------------------------------------------------------------- |
| **S**  | ≤ 7.0     | typically 1 | Directory `plans/<slug>/` | Simple, focused change. Usually one round handles it easily.  |
| **M**  | 7.1–11.0  | typically 1 | Directory `plans/<slug>/` | Meaty but cohesive. Usually one round, possibly a longer one. |
| **L**  | 11.1–15.0 | several     | Directory `plans/<slug>/` | Multi-round. Needs thoughtful splitting.                      |
| **XL** | ≥ 15.1    | many        | Directory `plans/<slug>/` | Complex. `STRATEGY.md` generated. Careful orchestration.      |

Round count is ultimately set by the Layer-2 round-splitting rules and is **uncapped**. The grade is
a descriptive difficulty signal, not a round ceiling or a format selector.

The adjusted-score thresholds are exactly the historical raw thresholds (5–7 / 8–11 / 12–15 / 16+),
so a `single-pass` executor (EF=1.0) recovers the old behavior precisely. Under `prex` (EF=1.5) a
borderline raw 8 → adjusted 5.33 → S (was M), borderline raw 12 → adjusted 8.0 → M (was L), and raw
20 → adjusted 13.33 → L (was XL): borderline tasks demote one grade, which is the intended effect of
the in-round review-loop. Under `limited` (EF=0.8) the same boundaries promote borderline tasks by
one grade.

This grade table is the **single source of truth for the difficulty grade**. Format is no longer
grade-selected — every plan is a directory. Skills and coordinators must not restate the mapping —
they point here.

## EF is mandatory — grade is descriptive

Always map the **adjusted** score (raw ÷ EF), never the raw score. Because raw caps at 20, the
highest grade the adjusted-score arithmetic can produce differs by executor (informational only —
grade does not cap rounds):

| Executor (EF)       | Max adjusted | Grades the arithmetic yields |
| ------------------- | ------------ | ---------------------------- |
| `prex` (1.5)        | 13.3         | S / M / L                    |
| `single-pass` (1.0) | 20.0         | S / M / L / XL               |
| `limited` (0.8)     | 25.0         | S / M / L / XL               |

The EF maps complexity to a descriptive per-dir grade. Round count is then chosen independently by
the Layer-2 round-splitting rules and is uncapped. Under any executor, more rounds are valid when
the work needs them; the hard ceiling is per-round `/prex` capacity (one Codex 600s session), not
total round count or grade.

## Two-layer decomposition

Layer 1 splits work by domain or scope into one or more **flat sibling** plan directories under
`plans/`. Related sibling dirs are wired together through the top-level `queue-plans.yaml`
`depends_on` field. One domain produces one dir; N domains produce N sibling dirs.

**Plan directories are always direct children of `plans/` (`plans/<slug>/`) and are never nested.**
Never place a plan directory inside another plan directory, and never create subdirectories within a
plan directory. All relationships and execution order are expressed **only** through the
`depends_on` field in the queue files, never through the filesystem hierarchy. A shared slug prefix
(e.g. `auth-backend`, `auth-frontend`) is a naming convention that groups related siblings — it is
**not** a parent directory.

Layer 2 grades each dir's difficulty with the five axes plus EF, then splits that dir into
**uncapped** rounds using the round-splitting rules below. The grade is **per-dir and descriptive**:
it no longer selects a format or caps round count.

Do not collapse the two layers. Multiple implementation **dirs** are a Layer-1 concern represented
in the top-level `queue-plans.yaml` with `depends_on`; multiple **rounds** in one dir are a Layer-2
concern represented in that plan's inner `queue-rounds.yaml`.

## Override guidance

The axes are structured judgment aids, not a rigid formula. Override when:

- **Bump up**: Few files but each requires 500+ lines of new code. Or the change is
  security-sensitive regardless of size. Or the implementation requires unfamiliar technology.
- **Bump down**: Many files but the change is mechanical (e.g., rename across 20 files). Or the
  codebase has strong test coverage that de-risks the change.

When overriding, note the reason under Decisions & Constraints — in the plan dir's `README.md` or in
the affected round files as appropriate.

## Round-splitting rules

Layer 2 uses these rules to split a plan dir into rounds. Round count is uncapped, but each round
must be a good `/prex` chunk: one cohesive unit of work, usually under 300 lines of plan text,
completable in one Codex 600s session, and never so small that a `/prex` session is wasteful. Apply
these rules in priority order:

1. **Module/subsystem boundaries** — group changes by the module they touch. Changes to the auth
   module go in one round; changes to the API layer go in another.

2. **Layer boundaries** — if the change spans layers, split bottom-up: data layer before business
   logic before API before UI. Each layer round produces a stable foundation for the next.

3. **Dependency order** — if round 2 depends on artifacts from round 1 (new types, new modules),
   they must be separate rounds. Never create circular dependencies between rounds.

4. **Cohesion over file count** — each round should deliver one coherent user-visible feature or one
   architectural layer. File count is incidental; mechanically-coupled changes belong together
   regardless of count. When the executor is `prex`, prefer fewer, larger, cohesive rounds — the
   in-round review-loop already de-risks size. When the executor is `limited`, prefer smaller
   rounds. The hard ceiling in all cases is work completable in one Codex 600s session.

5. **Atomic changes** — never split an atomic change across rounds. A type definition and all its
   consumers belong in the same round. A migration and the code that uses the new schema belong
   together.

6. **Foundations first** — shared foundations (types, interfaces, utilities, configuration) go in
   round 01. Consumer code goes in subsequent rounds.

7. **Tests with code** — tests go in the same round as the code they test. Exception: a dedicated
   integration/e2e testing round at the end, when the test suite exercises cross-round interactions.

## Reporting the classification

After classification, report to the user:

- The grade (S/M/L/XL) with a one-sentence rationale.
- The per-axis scores plus the executor factor (brief, not a full table — e.g., "files:2 cross-cut:1
  deps:2 novelty:3 risk:2 → raw 10 ÷ EF 1.5 (prex) → 6.7 → M").
- For L/XL: the proposed round split with topic summaries. Get user confirmation before generating.
