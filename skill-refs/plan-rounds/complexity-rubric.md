# Plan & Round Complexity Rubric

The canonical method for grading the complexity of an implementation plan, a single round, or a
queue of either. This file is the single source of truth for the complexity grade. Skills and
coordinators point here; they do not restate the axes, weights, or thresholds.

## What this grades, and how

The input is **prose**: a plan directory's `README.md`, a round file, or a queue. Grading is **a
priori** — it scores the *described* scope, structure, and risk **before** the code exists. Lines of
code and diff churn are post-hoc and mostly unavailable at grading time, so they are never the
input. The plan is treated as a proxy for the things empirical software engineering repeatedly finds
predictive of effort, defect risk, and comprehension burden.

The output is a **profile vector** of seven axis scores, a single **grade**, and the two or three
**drivers** that set it. Keep the vector — a single scalar hides which axis dominates.

Complexity is **intrinsic to the work**. This rubric answers exactly one question — *how complex is
this round or plan?* — and stops there. Two adjacent questions are deliberately out of scope and live
on their own: how capable each executor is, and how a grade is matched to an executor. Keeping the
three apart is what lets a round be re-evaluated without re-opening either of the others.

## The seven axes

Score each axis `0–4`: `0` absent/trivial · `1` low · `2` moderate · `3` high · `4` extreme.

### A — Scope / functional size
How much user- or system-visible behavior the plan adds, changes, or removes. Function Point Analysis
(IFPUG) and COSMIC size delivered functionality from requirements before code exists; COCOMO II treats
size as the primary effort input.

Read from prose: count of distinct behaviors, commands, endpoints, flags, modes, workflows, data
movements, and acceptance criteria; one-path fix vs. multi-case feature.

- `0` typo, copy, config-only — no behavior change
- `1` one narrow behavior or failure mode
- `2` several related behaviors in one component
- `3` multiple workflows, commands, or APIs
- `4` broad feature set, migration, or subsystem replacement

### B — Structural breadth
How many parts of the codebase must be understood or touched. Planned file/module breadth is a proxy
for coordination cost; dependency-graph defect studies show central, highly connected units are
riskier. Distinct from scope: a one-line semantic change rippling across 30 call sites is low scope,
high breadth.

Read from prose: named files/dirs/modules; "update all callers", "plumb through", "wire up"; number
of architectural layers (CLI → parser → domain → persistence → tests → docs); named discovery work.

- `0` no code, or one isolated doc/test file
- `1` one localized module plus nearby tests
- `2` 2–4 related files in one subsystem
- `3` several subsystems or architectural layers
- `4` repository-wide sweep, multi-package, or public-interface propagation

### C — Coupling / blast radius
Strength of dependence on, and effect to, other contracts, consumers, persisted state, or external
systems. Change-coupling studies tie co-change to defects; connascence frames coupling by strength,
locality, and degree. This axis carries the top weight because contract and migration changes fail
disproportionately.

Read from prose: public API/CLI/schema/protocol/migration/auth/permissions; compatibility
requirements; "all callers", "shared helper", "loader", "registry", "global"; temporal coupling
(ordering, concurrency, cache invalidation, background jobs).

- `0` no coupling; isolated text or fixture
- `1` local private helper or leaf behavior
- `2` shared helper or internal interface with limited callers
- `3` public contract, shared runtime path, persistence, or many callers
- `4` compatibility-, security-, concurrency-sensitive, or irreversible change

### D — Novelty / uncertainty
How much of the work is unknown, exploratory, or unrepresented by existing patterns. Estimation
methods (PERT three-point, Wideband Delphi, Planning Poker) all size uncertainty separately from
effort because uncertainty widens the estimate, not just its center.

Read from prose: "investigate", "figure out", "maybe", "if needed", "probably", "unknown"; new
library/architecture/domain or first use of an API; sparse detail; missing target files; unproven
assumptions; reliance on external specs.

- `0` fully mechanical; exact files and edits known
- `1` existing pattern copied with minor adaptation
- `2` some design judgment or API lookup required
- `3` substantial unknowns, new integration, or multiple viable approaches
- `4` research-heavy, ambiguous, novel architecture, or the plan itself is speculative

### E — Behavioral / cognitive complexity
How hard the intended behavior is to reason about. McCabe counts independent paths; Cognitive
Complexity (SonarSource) exists because path count alone does not match human understandability. From
prose, use described branching, state, and nested reasoning as the proxy.

Read from prose: conditionals, modes, fallback, precedence rules; state machines, retries,
concurrency, async, ordering, lifecycle hooks; parsing, validation, normalization; error-handling
matrices; "preserve existing behavior except…".

- `0` no logic
- `1` linear behavior with one condition
- `2` several cases or validation branches
- `3` interacting modes, precedence, parser/state behavior, or nontrivial failure handling
- `4` concurrency, distributed state, or many interacting invariants

### F — Verification cost
How hard it is to prove the implementation correct. McCabe tied complexity to basis-path testing;
INVEST includes "Testable"; agentic-coding difficulty often hinges on whether the test oracle is
clear, cheap, and reliable.

Read from prose: number and kind of required tests; need for integration/e2e/live/manual/migration/
snapshot tests; nondeterminism (time, network, filesystem, concurrency); unclear acceptance criteria;
golden-file or fixture updates.

- `0` no verification beyond lint/docs render
- `1` one unit test or existing-test update
- `2` focused unit tests plus one integration path
- `3` multiple test layers, fixtures, or hard-to-isolate behavior
- `4` live/manual/e2e, nondeterministic, migration rollback, security, or distributed verification

### G — Context load / agent suitability
How much dispersed information the agent running it must hold to succeed. "Lost in the Middle" shows model
accuracy degrades when relevant facts are buried in a long context; reasoning-effort scaling shows
harder, context-heavy tasks need more deliberation. This axis is LLM-specific and scored
independently of the nominal context-window size.

Read from prose: count of referenced docs, ADRs, prior plans, review comments, examples; "inspect
many files before editing"; cross-repo or generated-source context; long plans with scattered
constraints; reliance on subtle repository conventions.

- `0` self-contained one-paragraph edit
- `1` one local pattern to inspect
- `2` several local files or one reference doc
- `3` many files/docs, repo conventions, or hidden constraints
- `4` large context pack, cross-system reasoning, or relevant facts likely dispersed

## Scoring

### Weights and aggregate
Coupling, novelty, and verification failures are disproportionately expensive, so the aggregate is a
weighted sum, not a plain sum.

| Axis | A scope | B breadth | C coupling | D novelty | E behavior | F verification | G context |
| ---- | ------- | --------- | ---------- | --------- | ---------- | -------------- | --------- |
| Weight | 1.2 | 1.2 | 1.5 | 1.3 | 1.1 | 1.2 | 1.0 |

```text
score = 1.2·A + 1.2·B + 1.5·C + 1.3·D + 1.1·E + 1.2·F + 1.0·G        # range 0–34
```

### Hard escalation floors
A weighted sum under-rates a small change to a dangerous place. Apply these floors after computing
the score; the higher of (binned score, escalation floor) wins:

- any single axis `= 4` → minimum grade **High**
- `C ≥ 3` **and** `F ≥ 3` (risky **and** hard to verify) → minimum **High**
- `D ≥ 3` **and** `G ≥ 3` (unknown **and** dispersed context) → minimum **High**
- three or more axes at `≥ 3` → minimum **High**

### Clarity gate
Ambiguity is not additive effort — it can make the plan ungradeable. If fewer than five axes can be
scored from the plan, the result is **Unscorable / Needs decomposition**, never a low grade. A vague
plan is a planning defect, not a cheap task; send it back for detail or splitting.

## Grades

| Grade | Score | What it says about the work |
| ----- | ----- | --------------------------- |
| **Trivial**   | `0–4`     | mechanical and self-contained; one round holds it trivially |
| **Low**       | `>4–9`    | focused and low-risk; comfortably one round |
| **Moderate**  | `>9–16`   | substantive but cohesive; usually one round |
| **High**      | `>16–24`  | demanding; one cohesive round when the seams allow, otherwise split |
| **Very High** | `>24–30`  | too much for one cohesive round; decompose before executing unless a large round is deliberate |
| **Extreme**   | `>30`, or multi-`4` escalation | not a single round; must be decomposed |

**The grade is descriptive — it never caps round count.** "How hard is this?" (the grade) and "how
many rounds, split where?" (the decomposition rules below) are separate questions with separate
answers. A grade never means "at most N rounds": round count follows the natural seams of the work
and is uncapped. Difficulty *informs* splitting — Very High and Extreme are strong signals the work
will not fit one cohesive round — but that sets a floor on decomposition, never a ceiling on rounds.
Two plans of the same grade may split into one round or many, depending solely on where the work
cleaves.

## Deterministic vs. judgment signals

Per the skill/script boundary, mechanical extraction lives in `cog`; nuanced reads stay in a skill.
A `cog` extractor pre-scores the signals below from the plan text and a file graph, and flags the
axes that need a judgment pass; a `review-*` skill then refines those axes and emits the final grade.

**Mechanically extractable (cog):**

- named-file count, distinct subsystem/directory count (A, B, G)
- acceptance-criteria count; test keywords `unit|integration|e2e|live|manual|migration|fixture|snapshot` (F)
- public-contract keywords `CLI|flag|API|schema|config|env|protocol|database|migration` (C)
- coupling keywords `all callers|shared|global|loader|registry|hook|generated|compatibility` (C)
- uncertainty keywords `investigate|unknown|maybe|if needed|probably|explore|research` (D)
- behavioral keywords `fallback|precedence|retry|state|async|concurrent|cache|parse|validate` (E)
- count of linked docs/ADRs/plans/references (G)
- multiple unrelated bullet clusters or "and also" tasks → slice-quality flag (clarity gate)

**Requires a judgment pass (skill):**

- whether named files are central or leaf modules (deflates false-high B/C)
- whether a public interface is genuinely compatibility-sensitive
- whether the plan is vertically sliced or mixes independent concerns
- whether the listed tests actually cover the claimed behavior
- whether uncertainty is genuine or just cautious wording
- whether a broad change is mechanical and safe or semantically risky

## Scoring procedure

1. Parse the plan for the deterministic signals above.
2. Score all seven axes `0–4`, refining judgment axes with the code the plan references.
3. Apply the clarity gate; if it trips, stop at **Unscorable / Needs decomposition**.
4. Compute the weighted score.
5. Apply the escalation floors; take the higher grade.
6. Emit the vector, grade, and the top two or three drivers.
7. For **Very High** or **Extreme**, recommend a decomposition into rounds.

Output shape:

```yaml
grade: High
score: 22.0
axis_scores: { scope: 2, breadth: 3, coupling: 3, novelty: 2, behavior: 3, verification: 3, context: 2 }
drivers:
  - changes a public CLI contract and its completion/help references
  - touches a shared loader on the command-dispatch path
  - requires unit plus integration verification
recommendation: one cohesive round; split the contract change from the docs/completion updates only if they diverge
```

A short documentation task — one ADR plus one reference file, a few small edits, no logic
(`scope 1, breadth 1, coupling 1, novelty 1, behavior 0, verification 0, context 1` → `6.2`) — grades
**Low**: a focused, low-risk round, not the Moderate-or-higher it would draw from file count alone.

## Right-sizing and decomposition

A round is well-sized when it satisfies INVEST, reading *Valuable* as "leaves a durable
postcondition": **Independent, Estimable, Small, Testable**, mostly localized, free of large
unknowns, and able to fail without corrupting unrelated work.

Decompose before executing when any of these hold:

- more than one public-contract change
- one subsystem **plus** a migration
- `novelty ≥ 3`, or `verification = 4`
- any "and also" work that can be validated separately
- multiple unrelated acceptance-criteria clusters

Round-splitting follows these rules in priority order: split on **module/subsystem boundaries**
first; then **layer boundaries** bottom-up (data → logic → API → UI); then **dependency order**
(an artifact-producing round precedes its consumer; never cycle). Keep **atomic changes together** —
a type and its consumers, a migration and the code that uses the new schema, tests with the code they
test. Put **shared foundations** (types, interfaces, config) in the first round. Round count is
uncapped; the ceiling is one cohesive unit of work completable in a single execution session.

## Calibration

The weights, thresholds, and escalation rules are an informed starting point, not measured law. They
become defensible only against ground truth. Maintain a calibration loop: for each executed plan,
record the predicted grade and vector alongside the actual outcome (executor used, passes/re-rounds
needed, defects surfaced in review), and periodically refit the weights and bin boundaries where
prediction and outcome diverge. Register the calibration log as a perishable artifact so the sweep
revisits it (`docs/guides/maintenance-tracking.md`). Re-running this against the repo's own git
history is the first calibration pass.

## Evidence base

Each axis borrows a dimension from established work; none of these post-hoc code metrics is computed
from prose — they justify *what* to look for, while the calibration loop fixes the local numbers.

- McCabe, "A Complexity Measure," IEEE TSE 1976 (DOI 10.1109/TSE.1976.233837) — independent paths;
  grounds the behavioral and verification axes.
- G. Ann Campbell, "Cognitive Complexity," SonarSource — why understandability differs from path
  count. <https://www.sonarsource.com/docs/CognitiveComplexity.pdf>
- Halstead complexity measures — token/vocabulary/effort model; conceptual ancestor, post-code.
  <https://en.wikipedia.org/wiki/Halstead_complexity_measures>
- COCOMO II (USC) — size as primary effort input, plus scale factors and cost drivers; supports
  weighted multi-axis sizing.
- IFPUG Function Point Analysis — functional size from requirements before code. <https://ifpug.org/>
- COSMIC functional sizing — size via data movements; fits API/workflow/data-flow plans.
  <https://cosmic-sizing.org/>
- Nagappan & Ball, "Use of Relative Code Churn Measures to Predict System Defect Density," ICSE 2005 —
  change measures predict defects; grounds breadth and coupling.
  <https://www.microsoft.com/en-us/research/publication/use-of-relative-code-churn-measures-to-predict-system-defect-density/>
- D'Ambros, Lanza, Robbes, "On the Relationship Between Change Coupling and Software Defects," 2009 —
  co-change as a defect-risk dimension.
- Connascence — strength/locality/degree taxonomy of coupling. <https://connascence.io/>
- Wake, "INVEST in Good Stories" — right-sizing and decomposition criteria.
  <https://xp123.com/invest-in-good-stories-and-smart-tasks/>
- PERT three-point estimation and Planning Poker — model uncertainty separately from effort.
  <https://www.mountaingoatsoftware.com/agile/planning-poker>
- Liu et al., "Lost in the Middle: How Language Models Use Long Contexts," 2023 — score context load
  separately from window capacity. <https://arxiv.org/abs/2307.03172>
- SWE-bench and SWE-bench Verified — real coding-agent difficulty tracks issue clarity, tests, and
  repository context. <https://www.swebench.com/> · <https://openai.com/index/introducing-swe-bench-verified/>
