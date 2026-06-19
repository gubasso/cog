# Model/Effort Policy SoT: Policy Doc + Descriptive TOML Data + ADR

> Plan: model-effort-policy-and-rename | Round: 2 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog

## Context

`cog` skills choose a `model:` and `effort:` per task class, but the choice is an undocumented
convention with one outlier (`plans-revision` uses `model: sonnet` + `effort: high`; everything else
either uses `opus`+`low`, `haiku`, or no override). This round turns that convention into a
first-class, evidence-backed **single source of truth** and encodes the hard rule **never `model:
sonnet` — use `model: opus` + `effort: low` instead**.

The model/effort policy is **authoring-time guidance plus a recorded decision** — it governs how a
skill is *written* (its frontmatter) and which `cog codex-runner` profile a Codex call selects. It is
not a spec a skill loads mid-execution. Its correct Diátaxis home is therefore `docs/`:
`docs/reference/` for the policy prose, the TOML data, and the dated evidence; `docs/decisions/` for
the ADR. (No `skill-refs/` placement; this plan is independent of `cog-self-contained-skill-refs`.)

The data files are **TOML with deliberately descriptive fields**, so an AI agent reading them can
*reason about the correct classification of a new task*, not merely look up a value.

## Previous Rounds

`research-current-model-data` produced dated evidence references:
`docs/reference/models-reference-claude.md` (Opus 4.8 / Sonnet 4.6 / Haiku 4.5 / Fable 5 — pricing,
effort support, benchmarks) and `docs/reference/models-reference-codex.md` (gpt-5.5 / gpt-5.4 /
gpt-5.4-mini — pricing, effort token multipliers, benchmarks, API-only `-codex` caveat). Each carries
`Data collected: 2026-06-19`, `Sources:`, and `Revalidate by:` metadata. This round cites those.

## Scope of This Round

- IN scope:
  - `docs/reference/model-effort-policy.md` — the prose SoT (the "never sonnet" rule, the tier
    definitions, defaults for exploration/planning, how a skill author selects model+effort, how
    `cog codex-runner` profiles map).
  - `docs/reference/model-effort-claude.toml` and `docs/reference/model-effort-codex.toml` —
    structured tier data with descriptive fields.
  - A new ADR (next free number) recording the model/effort policy and the "never sonnet" decision.
  - Wiring: a non-negotiable line in `CLAUDE.md` and a guard/pointer in `AGENTS.md` pointing at the
    policy as SoT; index the new files in `docs/README.md`.
- OUT of scope:
  - Building a `cog model-policy` lookup command or changing `cog codex-runner` (note it as a
    follow-up; not in this plan).
  - Re-grading any skill's frontmatter (Round 3 handles `plans-revision` → opus/low; a broader sweep
    to align other skills is explicitly deferred — see "Next Round").
  - Deleting DocsNNotes sources (Round 3's gated cleanup).

## Current State

### Key Files

- `/workspaces/cog/docs/reference/` — destination for the policy + TOML data (Diátaxis "reference").
  Already holds the Round 1 evidence files.
- `/workspaces/cog/docs/decisions/` — ADRs `0001`…`0012` exist; `template.md` is the ADR template.
  **`0010` is already `0010-orchestration-env-first.md`.** The unrelated `cog-self-contained-skill-refs`
  plan adds another ADR (its own "0010" reference is stale → next free is `0013`). Pick the **next
  free number** here (expected `0013` or `0014` depending on run order) so the two do not collide.
- `/workspaces/cog/AGENTS.md` — carries "Orchestration Guards" and "Skill and Script Responsibility
  Boundary" sections; the place to add a model/effort-policy pointer/guard.
- `/workspaces/cog/CLAUDE.md` — carries a non-negotiable line pointing at
  `docs/decisions/0008-skill-script-boundary.md` and `docs/reference/skill-contract.md`; add a
  companion non-negotiable line pointing at the new policy + ADR.
- `/workspaces/cog/docs/README.md` — docs index (index only); add the new policy + TOML files.
- Observed current frontmatter convention (the evidence that the policy is formalizing, not
  inventing):

  ```text
  opus + effort: low   -> ast-grep, claudemd, osc-obs, pre-commit, review-findings,
                          suckless-patcher, test-review, skill-builder
  haiku (no effort)    -> gc, tsk-new
  (no model/effort)    -> ask, plan-writer, plan-writer-multi, plan-reviewer, prex,
                          review-loop, review-code-deep
  sonnet + high        -> plans-revision   (the lone outlier this policy retires)
  ```

### Existing Patterns

- Diátaxis: lookup facts → `docs/reference/`; decisions → `docs/decisions/`; `docs/README.md` is an
  index only.
- Markdown fenced blocks need a language (MD040). ADRs follow `docs/decisions/template.md`, are
  MADR-minimal, and are never deleted (superseding ADRs replace changed decisions).
- TOML is the chosen data format. Use multi-line basic strings (`"""…"""`) for the descriptive
  fields so they stay readable.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: model-effort-policy-sot`) `status` to
`doing`.

### Step 1: Author the descriptive TOML data files

Create `docs/reference/model-effort-claude.toml` and `docs/reference/model-effort-codex.toml`. Each
defines the task-class **tiers** with descriptive fields built to help an AI agent classify a new
task. Use this schema (Claude shown; mirror for Codex with model ids / `cog codex-runner` profiles
and the gpt tiers):

```toml
# Model/effort policy data — Claude. SoT for which model+effort a cog skill/task class uses.
# Evidence: docs/reference/models-reference-claude.md (Data collected: 2026-06-19).
schema_version = 1
provider = "claude"
# The hard rule, machine-readable:
forbidden_models = ["sonnet"]
sonnet_replacement = { model = "opus", effort = "low" }
session_default = { model = "opus", effort = "high", note = "exploration/planning skills set no override and ride this" }

[tiers.exploration]
model = "(session default)"
effort = "(session default)"
set_frontmatter = false
use_when = """Open-ended reasoning: exploring a codebase, planning, asking/answering questions,
designing an approach. The hard reasoning happens DURING the task."""
signals = ["unbounded search space", "decisions not yet made", "needs full session judgment", "plan/ask/review-design work"]
anti_signals = ["a detailed plan already exists", "purely mechanical/deterministic steps"]
examples = ["ask", "plan-writer", "plan-writer-multi", "plan-reviewer", "prex", "review-loop", "review-code-deep"]
reference_docs = ["docs/reference/models-reference-claude.md"]
rationale = "Riding the session default keeps the strongest model+effort for genuinely open work; pinning would cap it."
escalation = "Author may override per case (e.g. effort=xhigh) when a specific task is unusually hard; document the override."

[tiers.procedural]
model = "opus"
effort = "low"
set_frontmatter = true
use_when = """Executes a well-structured, detailed procedure where the hard decisions are already
made and most logic is delegated to scripts/cog subcommands, but some judgment remains."""
signals = ["repeatable runbook", "deterministic core delegated to cog", "bounded judgment", "executes an existing detailed plan"]
anti_signals = ["novel design", "open-ended exploration"]
examples = ["pre-commit", "test-review", "review-findings", "claudemd", "osc-obs", "suckless-patcher", "ast-grep", "skill-builder", "review-implementation-plans"]
reference_docs = ["docs/reference/models-reference-claude.md"]
rationale = "opus+low beats sonnet on quality at comparable cost; this is the canonical 'never sonnet' replacement tier."
escalation = "Raise to effort=medium for a heavier detailed-plan execution; never drop to sonnet."

[tiers.routine]
model = "haiku"
effort = "(none)"
set_frontmatter = true
use_when = """Bare execution of a simple routine: the overwhelming majority of logic is deterministic
and delegated to scripts/orchestrators; the model just sequences calls and formats output."""
signals = ["thin orchestration over cog subcommands", "no real reasoning", "fast/cheap is the priority"]
anti_signals = ["any meaningful judgment", "multi-step design"]
examples = ["gc", "tsk-new"]
reference_docs = ["docs/reference/models-reference-claude.md"]
rationale = "Haiku is fastest/cheapest and sufficient when logic lives in scripts. Haiku does not take an effort level."
escalation = "If the routine starts needing judgment, promote to the procedural tier (opus+low)."
```

Mirror the same tier names and descriptive fields in `model-effort-codex.toml`, using the
Codex-selectable models and `cog codex-runner` / `codex-session` profile intuition from
`docs/reference/models-reference-codex.md`:

```toml
# Model/effort policy data — Codex. SoT for codex-session / cog codex-runner model+effort.
schema_version = 1
provider = "codex"
session_default = { model = "gpt-5.5", effort = "medium" }
# Tiers mirror the Claude file:
# exploration -> (session default) gpt-5.5 + medium
# procedural  -> gpt-5.5 + medium  (heavy detailed-plan execution may use low; never an anti-pattern tier)
# routine     -> gpt-5.4-mini + medium
# (Fill each [tiers.*] with the same descriptive fields: use_when/signals/anti_signals/examples/
#  reference_docs/rationale/escalation, and note -codex models are API-only and never pinned.)
```

Tune the exact Codex per-tier values to match the revalidated evidence (gpt-5.5 @ medium is the
quality default; high is escalation-only; gpt-5.4 @ high is an anti-pattern; gpt-5.4-mini @ medium
for trivial work).

### Step 2: Author `docs/reference/model-effort-policy.md`

Write the prose SoT. It must state, unambiguously:

1. **The hard rule:** never `model: sonnet`; use `model: opus` + `effort: low` instead.
2. **The default rule:** exploration/planning skills set no `model:`/`effort:` override and ride the
   session default (Claude: Opus + high; Codex: gpt-5.5 + medium), which an author may override per
   case with justification.
3. **The tier table** (mirrors the TOML; do not duplicate values that can drift — point at the TOML
   as the machine-readable SoT and keep the prose as the human-readable rationale).
4. **How a skill author chooses:** read the tiers, match `use_when`/`signals`, set frontmatter (or
   not) accordingly; for Codex, select the `cog codex-runner` profile per the codex TOML.
5. **Evidence pointer:** `docs/reference/models-reference-{claude,codex}.md`, with their
   `Data collected` dates, and a note that the policy is revalidated when that evidence is.

### Step 3: Write the policy ADR

Create the next-free-numbered ADR (expected `docs/decisions/0013-model-effort-policy.md` or `0014`,
whichever is free) from `docs/decisions/template.md`. Record: the decision (the tier policy + "never
sonnet → opus+low"), the context (the implicit convention + the lone sonnet outlier + the pricing/
quality evidence), the consequences (skills declare frontmatter per tier;
`plans-revision`/`review-implementation-plans` re-graded to opus+low in Round 3), and the SoT
location (`docs/reference/model-effort-policy.md` + the two TOML files). Confirm the chosen number is
unused.

### Step 4: Wire the SoT into AGENTS.md, CLAUDE.md, and the docs index

- `CLAUDE.md`: add a non-negotiable line pointing at the new ADR and `docs/reference/
  model-effort-policy.md` as the SoT for skill model/effort selection, alongside the existing
  skill-script-boundary line.
- `AGENTS.md`: add a short pointer/guard (near "Skill and Script Responsibility Boundary" or
  "Orchestration Guards") stating that skill `model:`/`effort:` choices follow
  `docs/reference/model-effort-policy.md` and that `model: sonnet` is forbidden (use opus+low).
- `docs/README.md`: index the policy doc and the two TOML files (index only).

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: model-effort-policy-sot`) `status` to
   `done`.

## Acceptance Criteria

- [ ] `docs/reference/model-effort-policy.md`, `docs/reference/model-effort-claude.toml`, and
      `docs/reference/model-effort-codex.toml` exist; the TOML files carry the descriptive fields
      (`use_when`, `signals`, `anti_signals`, `examples`, `reference_docs`, `rationale`,
      `escalation`) for each tier.
- [ ] The TOML and policy both encode `forbidden_models = ["sonnet"]` / "never sonnet → opus+low".
- [ ] The TOML files cite the Round 1 evidence references.
- [ ] A new ADR (next free number, not `0010`–`0012`) records the policy and the "never sonnet"
      decision.
- [ ] `CLAUDE.md` and `AGENTS.md` point at the policy as SoT and state the no-sonnet rule; the new
      files are indexed in `docs/README.md`.
- [ ] All fenced code blocks declare a language (MD040 clean).
- [ ] This plan's `queue-rounds.yaml` shows round `model-effort-policy-sot` as `done`.

## Next Round

`rename-to-review-implementation-plans` applies the policy: it renames the `plans-revision` skill +
`cog` commands to `review-implementation-plans` and re-grades the skill to `model: opus` + `effort:
low` (the canonical "never sonnet" worked example), then retires the DocsNNotes model-reference
sources. A broader sweep to align *other* skills' frontmatter with the new tiers is intentionally
deferred beyond this plan.
